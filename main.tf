variable "home_ip" {
  description = "Your home IP"
  type        = string
}

provider "aws" {
  region = "us-east-2"
}

resource "random_id" "unique_suffix" {
  byte_length = 4
}

resource "aws_dynamodb_table" "ai_responses" {
  name = "aiResponseTable-${random_id.unique_suffix.hex}"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "model_id"

  attribute {
    name = "model_id"
    type = "S"
  }
}

resource "aws_security_group" "ai_sg" {
  name        = "aiAccess-${random_id.unique_suffix.hex}"
  description = "Allow SSH and HTTP from home"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH from home"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
   cidr_blocks = ["${var.home_ip}/32"]
  }

  ingress {
    description = "HTTP from home"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["${var.home_ip}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"]
}

resource "aws_iam_role" "ec2_role" {
  name = "bedrock-dynamodb-access-${random_id.unique_suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "ec2_policy" {
  name = "bedrock-dynamodb-policy-${random_id.unique_suffix.hex}"
  role = aws_iam_role.ec2_role.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["bedrock:*", "dynamodb:*"],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "bedrock-instance-profile-${random_id.unique_suffix.hex}"
  role = aws_iam_role.ec2_role.name
}


resource "aws_instance" "ubuntu_bedrock_client" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.ai_sg.id]
 
  iam_instance_profile   = aws_iam_instance_profile.ec2_instance_profile.name

  user_data = <<-EOF
    #!/bin/bash
    apt update -y
    apt install -y python3-pip
    pip3 install boto3 flask

    # Write script to call Bedrock (you'll need credentials via instance profile or env vars)
    cat <<PYTHON > /home/ubuntu/bedrock_query.py
import boto3
import json

models = [
  "anthropic.claude-3-sonnet-20240229-v1:0",
  "ai21.j2-ultra-v1",
  "amazon.titan-text-lite-v1",
  "meta.llama3-70b-instruct-v1:0",
  "cohere.command-r-plus-v1:0"
]

prompt = "pitch me your capabilities for creating financial plans using between 200-550 words"
ddb = boto3.resource('dynamodb', region_name='us-east-2')
table = ddb.Table("${aws_dynamodb_table.ai_responses.name}")

client = boto3.client('bedrock-runtime')

for model_id in models:
    try:
        response = client.invoke_model(
            body=json.dumps({ "prompt": prompt }),
            modelId=model_id,
            accept="application/json",
            contentType="application/json"
        )
        text = json.loads(response['body'].read())['completion']
        table.put_item(Item={ 'model_id': model_id, 'response': text })
    except Exception as e:
        print(f"Error with model {model_id}: {e}")
PYTHON

    python3 /home/ubuntu/bedrock_query.py

    # Launch simple Flask server to serve stored data
    cat <<FLASK > /home/ubuntu/app.py
from flask import Flask
import boto3

app = Flask(__name__)
ddb = boto3.resource('dynamodb', region_name='us-east-2')
table = ddb.Table("${aws_dynamodb_table.ai_responses.name}")

@app.route("/")
def home():
    items = table.scan().get("Items", [])
    html = "<h1>AI Responses</h1>"
    for item in items:
        html += f"<h2>{item['model_id']}</h2><p>{item['response']}</p><hr>"
    return html

@app.route("/logs")
def logs():
    with open("/home/ubuntu/bedrock.log") as f:
        return "<pre>" + f.read() + "</pre>"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
FLASK

    nohup python3 /home/ubuntu/app.py &
  EOF

  tags = {
    Name = "Ubuntu-Bedrock-Client"
  }
}

output "public_ip" {
  value = aws_instance.ubuntu_bedrock_client.public_ip
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.ai_responses.name
}
