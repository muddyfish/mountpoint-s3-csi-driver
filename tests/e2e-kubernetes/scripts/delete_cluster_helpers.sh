function delete_vpc_endpoint() {
  VPC_ID=${1}
  REGION=${2}
  # GuardDuty creates resources (namely an endpoint and a security group), which are not handled by eks cfn stack and prevents it from being deleted
  # https://docs.aws.amazon.com/guardduty/latest/ug/runtime-monitoring-agent-resource-clean-up.html#clean-up-guardduty-agent-resources-process
  ENDPOINT=$(aws ec2 describe-vpc-endpoints --region "${REGION}" | jq -r --arg VPC_ID "$VPC_ID" '.["VpcEndpoints"][] | select(.["VpcId"]==$VPC_ID and .["Tags"][0]["Key"]=="GuardDutyManaged" and .["Tags"][0]["Value"]=="true") | .["VpcEndpointId"]')
  if [ -n "$ENDPOINT" ]; then
    aws ec2 delete-vpc-endpoints --region "${REGION}" --vpc-endpoint-ids "${ENDPOINT}"
  fi
}

function delete_security_groups() {
  VPC_ID=${1}
  REGION=${2}

  SECURITY_GROUPS=$(aws ec2 describe-security-groups --region "${REGION}" | jq -r --arg VPC_ID "$VPC_ID" '.["SecurityGroups"][] | select(.["VpcId"]==$VPC_ID and .["GroupName"]!="default") | .["GroupId"]')
  if [ -n "$SECURITY_GROUPS" ]; then
    # security group deletion only succeeds after a certain step of stack deletion was passed (namely subnets deletion),
    # after which stack deletion is blocked because of the security group, so we retry here until this step is completed
    echo "${SECURITY_GROUPS}" | while IFS= read -r SECURITY_GROUP ; do
      delete_security_group "${REGION}" "${SECURITY_GROUP}"
    done
  fi
}

function delete_enis() {
  VPC_ID=${1}
  REGION=${2}

  # https://github.com/eksctl-io/eksctl/issues/7589
  ENIS=$(aws ec2 describe-network-interfaces --region "${REGION}" | jq -r --arg VPC_ID "$VPC_ID" '.["NetworkInterfaces"][] | select(.["VpcId"]==$VPC_ID) | .NetworkInterfaceId')
  if [ -n "$ENIS" ]; then
    echo "${ENIS}" | while IFS= read -r ENI_ID ; do
      delete_eni "${REGION}" "${ENI_ID}"
    done
  fi
}

function delete_security_group() {
  REGION=${1}
  SECURITY_GROUP=${2}

  remaining_attempts=20
  while (( remaining_attempts-- > 0 ))
  do
      if output=$(aws ec2 delete-security-group --region "${REGION}" --group-id "${SECURITY_GROUP}" 2>&1); then
        return
      fi
      if [[ $output == *"InvalidGroup.NotFound"* ]]; then
        return
      fi
      sleep 30
  done
}

function delete_eni() {
  REGION=${1}
  ENI_ID=${2}

  remaining_attempts=20
  while (( remaining_attempts-- > 0 ))
  do
      if output=$(aws ec2 delete-network-interface --network-interface-id "${ENI_ID}" --region "${REGION}" 2>&1); then
        return
      fi
      if [[ $output == *"InvalidNetworkInterfaceID.NotFound"* ]]; then
        return
      fi
      sleep 30
  done
}
