import json
import boto3
import os
import re

s3 = boto3.client("s3")
BUCKET = os.environ["RAW_BUCKET"]
EXPIRATION = 300  # 5 minutos para completar el upload

def lambda_handler(event, context):
    try:
        body = json.loads(event["body"])
    except (KeyError, json.JSONDecodeError):
        return {"statusCode": 400, "body": json.dumps({"error": "body inválido"})}

    product_id = body.get("product_id")
    filename   = body.get("filename")
    content_type = body.get("content_type")

    if not all([product_id, filename, content_type]):
        return {"statusCode": 400, "body": json.dumps({"error": "faltan campos"})}

    # Sanitización: elimina cualquier caracter fuera de letras, números, guiones y punto
    # Sin esto un filename como "../../etc/passwd" podría manipular la ruta en S3
    safe_filename = re.sub(r"[^a-zA-Z0-9._-]", "_", filename)
    key = f"raw/{product_id}/{safe_filename}"

    # ContentType va en Params, no en headers
    # La presigned URL firma exactamente estos parámetros
    # Si el cliente sube con un ContentType diferente, S3 rechaza el request
    url = s3.generate_presigned_url(
        "put_object",
        Params={
            "Bucket": BUCKET,
            "Key": key,
            "ContentType": content_type
        },
        ExpiresIn=EXPIRATION
    )

    return {
        "statusCode": 200,
        "body": json.dumps({"upload_url": url, "key": key})
    }
