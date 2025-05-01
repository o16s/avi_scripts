#!/bin/bash
source .env

# Test file
echo "Test content" > test_file.txt

# Debug info
echo "==== AZURE CONNECTION DETAILS ===="
echo "Storage Account: $STORAGE_ACCOUNT_NAME"
echo "Container: $CONTAINER_NAME"
echo "SAS Token (first 20 chars): ${SAS_TOKEN:0:20}..."
echo "SAS Token length: ${#SAS_TOKEN}"
echo

# Construct the URL for testing
TEST_BLOB="test_upload_$(date +%s).txt"
FULL_URL="https://$STORAGE_ACCOUNT_NAME.blob.core.windows.net/$CONTAINER_NAME/$TEST_BLOB$SAS_TOKEN"

echo "==== REQUEST DETAILS ===="
echo "URL: $FULL_URL"
echo
echo "==== SENDING TEST REQUEST WITH FULL TRACE ===="

# Verbose upload with full trace
curl -v -X PUT \
    --max-time 15 \
    -H "x-ms-version: 2023-01-03" \
    -H "x-ms-date: $(date -u '+%a, %d %b %Y %H:%M:%S GMT')" \
    -H "x-ms-blob-type: BlockBlob" \
    -H "Content-Length: $(wc -c < test_file.txt)" \
    --data-binary @test_file.txt \
    "$FULL_URL"

echo
echo "==== END TEST ===="
