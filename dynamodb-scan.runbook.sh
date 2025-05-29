#!/bin/bash

# -------- Select a table or index --------
TABLE_NAME='{{ .tableName | type "select" | description "Select a table or index" | options "Table - Employee" | default "Table - Employee" }}'

# -------- Filters - optional --------
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
echo "🔍 Running Scan on Employee table:"
echo "$CMD"
echo ""
eval "$CMD"
