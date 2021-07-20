from pynamodb.models import Model
from pynamodb.attributes import UnicodeAttribute, NumberAttribute
from dotenv import load_dotenv
import os

load_dotenv()

class User(Model):
    class Meta:
        table_name = "users"
        region = "us-east-1"
        # host = os.getenv("DYNAMODB_URL")

    id = UnicodeAttribute(hash_key=True)
    name = UnicodeAttribute()
    followers_count = NumberAttribute()
