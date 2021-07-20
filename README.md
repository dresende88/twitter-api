# twitter-api
Sample twitter API app


Exemplo de script que consulta tags no twitter.

O código foi criado no terraform usando a cloud pública AWS.

Para executá-lo instalar as dependencias abaixo:

Terraform 1.0.2
AWS CLI
docker

Configurar as crenciais da AWS no terminal
Configurar um bucket s3 para usar como estado no terraform (main.tf, linha 3)
Adicionar as credenciais da API do twitter como variável de ambiente (main.tf, linhas 163, 164, 165, 166)

Fazer o build da imagem com os seguintes comandos:

docker build -t twitter-api .

docker tag twitter-api:latest 208329978497.dkr.ecr.us-east-1.amazonaws.com/twitter-api:latest

Executar os comandos abaixo para provisionar a infraestrutura:

terraform init

terraform apply

Depois que o ambiente estiver criado, no serviço lambda crie um teste e execute e verifique se os dados estão sendo retornados do twitter.

As informações serão inseridas no dynamodb, porém não terminado. Deste modo os dados serão inseridos apenas na tabela user.

Na aba monitoring é possível ver métricas de sucesso e erros de execução.

Os logs são enviados para o cloudwatch logs.