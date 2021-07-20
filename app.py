import twitter
from dotenv import load_dotenv
import os
from user import User

def handler(event, context):
    print("Iniciando scripts...")
    try:
        load_dotenv()
        AUTHENTICATION = {
            "consumer_key": os.getenv("CONSUMER_KEY"),
            "consumer_secret": os.getenv("CONSUMER_SECRET"),
            "access_token_key": os.getenv("ACCESS_TOKEN"),
            "access_token_secret": os.getenv("ACCESS_TOKEN_SECRET")    
        }
        hashtags = [
            "%23openbanking",
            "%23remediation",
            "%23devops",
            "%23sre",
            "%23microservices",
            "%23observability",
            "%23oauth",
            "%23metrics",
            "%23logmonitoring",
            "%23opentracing"
        ]

        users_with_more_followers = []
        pages = 10
        print("Autenticando na API do twitter...")
        api = twitter.Api(**AUTHENTICATION)
        for hashtag in hashtags:
            query_string = "q={}&src=typed_query&count={}".format(hashtag, pages)
            tweets = api.GetSearch(raw_query=query_string)

            for tweet in tweets:
                users_with_more_followers.append({ 
                    "user_id": tweet.user.id_str,
                    "followers_count": tweet.user.followers_count,
                    "name": tweet.user.name,
                    "hashtags": list(map(lambda x: x.AsDict()["text"], tweet.hashtags)) 
                })

            users_with_more_followers \
                .sort(key=lambda x: x["followers_count"], reverse=True)
        
        print("Inserindo dados no dynamodb...")
        for u in users_with_more_followers:
            print(u)
            user = User(u["user_id"], name=u["name"], followers_count=u["followers_count"])
            user.save()
        return []

    except Exception as e:
        print(e)