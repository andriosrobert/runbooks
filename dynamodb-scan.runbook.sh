#!/bin/bash

# -------- Scan or query items --------
OPERATION='{{ .operation | type "select" | description "Scan or query items" | options "Scan" "Query" | default "Scan" }}'

# -------- Select a table or index --------
TABLE_NAME='{{ .tableName | type "select" | description "Select a table or index" | options "Table - Employee" | default "Table - Employee" }}'

# -------- Select attribute projection --------
PROJECTION='{{ .projection | type "select" | description "Select attribute projection" | options "All attributes" | default "All attributes" }}'

# -------- Filters - optional --------
# Filter 1
FILTER_ATTRIBUTE='{{ .filterAttribute | description "Attribute name" }}'
FILTER_CONDITION='{{ .filterCondition | type "select" | description "Condition" | options "Equal to" | default "Equal to" }}'
FILTER_TYPE='{{ .filterType | type "select" | description "Type" | options "String" | default "String" }}'
FILTER_VALUE='{{ .filterValue | description "Enter attribute value" }}'

# -------- Build and Run Command --------
CMD="aws dynamodb scan --table-name Employee"

# Add filter if provided
if [ -n "$FILTER_ATTRIBUTE" ] && [ -n "$FILTER_VALUE" ]; then
    CMD+=" --filter-expression \"#attr = :val\""
    CMD+=" --expression-attribute-names '{\"#attr\": \"$FILTER_ATTRIBUTE\"}'"
    CMD+=" --expression-attribute-values '{\":val\": {\"S\": \"$FILTER_VALUE\"}}'"
fi

# Run the command
echo "🔍 Running Scan:"
echo "$CMD"
echo ""
eval "$CMD"
