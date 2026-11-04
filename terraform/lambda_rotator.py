import boto3

sm = boto3.client("secretsmanager")


def lambda_handler(event, context):
    arn, token, step = event["SecretId"], event["ClientRequestToken"], event["Step"]

    if step == "createSecret":
        # Read the current value (demonstrates the real-world pattern of reading AWSCURRENT)
        current = sm.get_secret_value(SecretId=arn, VersionStage="AWSCURRENT")
        print(f"Read AWSCURRENT version {current['VersionId']}")  # never log SecretString

        pw = sm.get_random_password(PasswordLength=32, ExcludePunctuation=True)["RandomPassword"]
        try:
            sm.put_secret_value(SecretId=arn, ClientRequestToken=token,
                                SecretString=pw, VersionStages=["AWSPENDING"])
        except sm.exceptions.ResourceExistsException:
            pass  # a previous attempt already created this version
    elif step in ("setSecret", "testSecret"):
        pass  # no downstream system to update or test for a standalone secret
    elif step == "finishSecret":
        stages = sm.describe_secret(SecretId=arn)["VersionIdsToStages"]
        current = next(v for v, s in stages.items() if "AWSCURRENT" in s)
        if current != token:
            sm.update_secret_version_stage(SecretId=arn, VersionStage="AWSCURRENT",
                                           MoveToVersionId=token, RemoveFromVersionId=current)
    else:
        raise ValueError(f"Unknown step: {step}")
        
