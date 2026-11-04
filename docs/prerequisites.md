# Create S3 bucket to store Terraform state files and enable versioning

1. Create bucket:
    ```bash
    REGION="eu-west-1"
    BUCKET_NAME="top-secret-terraform-state"

    aws s3 mb s3://${BUCKET_NAME} --region $REGION
    ```
2. Enable versioning on the bucket for quick state file error recovery:
    ```bash
    aws s3api put-bucket-versioning --bucket ${BUCKET_NAME} \
    --versioning-configuration Status=Enabled

    ```

# Delete Prerequisites

1. Delete bucket
    ```bash
    REGION="eu-west-1"
    BUCKET_NAME="top-secret-terraform-state"

    aws s3api delete-objects \
    --bucket $BUCKET_NAME \
    --delete "$(aws s3api list-object-versions \
        --bucket  $BUCKET_NAME \
        --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
        --output json)"

    aws s3api delete-objects \
    --bucket $BUCKET_NAME \
    --delete "$(aws s3api list-object-versions \
        --bucket $BUCKET_NAME \
        --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
        --output json)"

    aws s3 rb s3://$BUCKET_NAME --region $REGION
    ```