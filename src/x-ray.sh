#!/bin/bash

########################
# include the magic
########################
. demo-magic.sh -d
#DEMO_PROMPT="${GREEN}➜ ${CYAN}\W "
PROMPT_TIMEOUT=60
# hide the evidence
clear

#Create stack

pe "aws cloudformation create-stack --stack-name x-ray --template-body https://raw.githubusercontent.com/jicowan/ecsworkshop-xray/master/src/x-ray.yaml"

#Create a task role that allows the task to write traces to AWS X-Ray.

pe "export TASK_ROLE_NAME=\$(aws iam create-role --role-name XrayRole --assume-role-policy-document file://ecs-trust-pol.json --query 'Role.RoleName' --output text)"
pe "export XRAY_POLICY_ARN=\$(aws iam create-policy --policy-name XrayPolicy --policy-document file://xray-pol.json --query 'Policy.Arn' --output text)"
pe "aws iam attach-role-policy --role-name \$TASK_ROLE_NAME --policy-arn \$XRAY_POLICY_ARN"

#Export the Arns of the task role and the task execution role.

pe "export TASK_ROLE_ARN=\$(aws iam get-role --role-name XrayRole --query \"Role.Arn\" --output text)"
pe "export TASK_EXECUTION_ROLE_ARN=\$(aws iam get-role --role-name ecsTaskExecutionRole --query \"Role.Arn\" --output text)"

#Extract the outputs from the CFN template. 

pe "export ECS_CLUSTER=\$(aws cloudformation describe-stacks --stack-name x-ray --query 'Stacks[0].Outputs[?OutputKey==\`EcsClusterName\`][OutputValue] | [0][0]' --output text)"
pe "export SUBNET_ID_1=\$(aws cloudformation describe-stacks --stack-name x-ray --query 'Stacks[0].Outputs[?OutputKey==\`Subnet1\`][OutputValue] | [0][0]' --output text)"
pe "export SUBNET_ID_2=\$(aws cloudformation describe-stacks --stack-name x-ray --query 'Stacks[0].Outputs[?OutputKey==\`Subnet2\`][OutputValue] | [0][0]' --output text)"
pe "export SERVICE_B_ENDPOINT=\$(aws cloudformation describe-stacks --stack-name x-ray --query 'Stacks[0].Outputs[?OutputKey==\`ServiceBEndpoint\`][OutputValue] | [0][0]' --output text)"
pe "export TARGET_GROUP_SERVICE_A=\$(aws cloudformation describe-stacks --stack-name x-ray --query 'Stacks[0].Outputs[?OutputKey==\`TargetGroupServiceA\`][OutputValue] | [0][0]' --output text)"
pe "export TARGET_GROUP_SERVICE_B=\$(aws cloudformation describe-stacks --stack-name x-ray --query 'Stacks[0].Outputs[?OutputKey==\`TargetGroupServiceB\`][OutputValue] | [0][0]' --output text)"
pe "export FARGATE_SECURITY_GROUP=\$(aws cloudformation describe-stacks --stack-name x-ray --query 'Stacks[0].Outputs[?OutputKey==\`FargateSecurityGroup\`][OutputValue] | [0][0]' --output text)"

#Configure ecs-cli

pe "ecs-cli configure --cluster \$ECS_CLUSTER --region us-west-2"

#Build and push the containers to ECR.

pe "docker build -t service-b ./service-b/"
pe "ecs-cli push service-b"
pe "docker build -t service-a ./service-a/"
pe "ecs-cli push service-a"

#Create logs groups.

pe "aws logs create-log-group --log-group-name /ecs/service-b"
pe "aws logs create-log-group --log-group-name /ecs/service-a" 

#Set the registry URLs

pe "export REGISTRY_URL_SERVICE_B=\$(aws ecr describe-repositories --repository-name service-b --query 'repositories[].repositoryUri' --output text)"
pe "export REGISTRY_URL_SERVICE_A=\$(aws ecr describe-repositories --repository-name service-a --query 'repositories[].repositoryUri' --output text)"

#Create service B.

pe "cd ./service-b"
pe "../envsubst < docker-compose.yml-template > docker-compose.yml"
pe "../envsubst < ecs-params.yml-template > ecs-params.yml"
pe "ecs-cli compose service up --deployment-max-percent 100 --deployment-min-healthy-percent 0 --target-group-arn \$TARGET_GROUP_SERVICE_B --launch-type FARGATE --container-name service-b --container-port 8080"
pe "cd .."

#Create service A.

pe "cd ./service-a"
pe "../envsubst < docker-compose.yml-template > docker-compose.yml"
pe "../envsubst < ecs-params.yml-template > ecs-params.yml" 
pe "ecs-cli compose service up --deployment-max-percent 100 --deployment-min-healthy-percent 0 --target-group-arn \$TARGET_GROUP_SERVICE_A --launch-type FARGATE --container-name service-a --container-port 8080"
pe "cd .."