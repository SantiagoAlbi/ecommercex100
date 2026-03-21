import json
import boto3
import os
from PIL import Image
import io

s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")

RAW_BUCKET       = os.environ["RAW_BUCKET"]
PROCESSED_BUCKET = os.environ["PROCESSED_BUCKET"]
TABLE_NAME       = os.environ["DYNAMODB_TABLE"]
CLOUDFRONT_URL   = os.environ["CLOUDFRONT_URL"]

VARIANTS = {
    "thumb":  (150, 150),
    "medium": (600, 600),
    "large":  (1200, 1200),
}

def lambda_handler(event, context):
    for record in event["Records"]:
        # Primer nivel de parsing: envelope de SQS
        # El body del record SQS es el evento S3 serializado como string
        s3_event = json.loads(record["body"])

        # Segundo nivel: dentro del evento S3 están los objetos afectados
        for s3_record in s3_event["Records"]:
            bucket = s3_record["s3"]["bucket"]["name"]
            key    = s3_record["s3"]["object"]["key"]

            process_image(bucket, key)

def process_image(bucket, key):
    # Descargar imagen original desde raw/
    response = s3.get_object(Bucket=bucket, Key=key)
    image_data = response["Body"].read()

    image = Image.open(io.BytesIO(image_data))

    # RGBA y P no son compatibles con WebP sin conversión previa
    if image.mode in ("RGBA", "P"):
        image = image.convert("RGBA")
    else:
        image = image.convert("RGB")

    # Extraer product_id y filename del key: raw/{product_id}/{filename}
    parts    = key.split("/")
    product_id = parts[1]
    filename   = parts[2].rsplit(".", 1)[0]  # sin extensión

    urls = {}
    table = dynamodb.Table(TABLE_NAME)

    for variant_name, (width, height) in VARIANTS.items():
        variant = image.copy()
        variant.thumbnail((width, height), Image.LANCZOS)

        buffer = io.BytesIO()

        # quality=85: balance entre calidad visual y tamaño
        # 100 es lossless, por debajo de 75 empieza a notarse degradación
        variant.save(buffer, format="WEBP", quality=85)
        buffer.seek(0)

        output_key = f"{variant_name}/{product_id}/{filename}.webp"

        s3.put_object(
            Bucket=PROCESSED_BUCKET,
            Key=output_key,
            Body=buffer,
            ContentType="image/webp",
            # Le dice al browser y a CloudFront cuánto tiempo cachear
            CacheControl="max-age=31536000"
        )

        urls[variant_name] = f"{CLOUDFRONT_URL}/{output_key}"

    # Guardar metadata y URLs en DynamoDB
    table.put_item(Item={
        "image_id":  f"{product_id}/{filename}",
        "product_id": product_id,
        "urls":       urls,
    })
