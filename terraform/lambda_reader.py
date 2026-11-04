import json
import logging
import os

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

SECRET_ID = os.environ["SECRET_ID"]
secrets_client = boto3.client("secretsmanager")


def lambda_handler(event, context):
    try:
        response = secrets_client.get_secret_value(SecretId=SECRET_ID)
    except ClientError as err:
        logger.error(
            "Could not read secret %s: %s",
            SECRET_ID,
            err.response["Error"]["Code"],
        )
        raise

    secret_value = response.get("SecretString", "")
    logger.info("Read secret %s (version %s)", SECRET_ID, response["VersionId"])

    # Deliberately never log or return the secret value itself:
    # function responses and CloudWatch logs are far less protected than the secret.
    return {
        "statusCode": 200,
        "body": json.dumps(
            {
                "secret": SECRET_ID,
                "versionId": response["VersionId"],
                "valueLength": len(secret_value),
            }
        ),
    }
