#!/bin/bash

# -------- Table and Index --------
TABLE_NAME='{{ .tableName | type "select" | description "Select the DynamoDB table" | options "Movies" "Users" "Orders" }}'
INDEX_NAME='{{ .indexName | description "Optional index to query (leave blank for primary index)" }}'

# -------- Partition Key Input --------
PARTITION_KEY='{{ .partitionKey | description "Partition key attribute name (e.g., year)" | required "Partition key is required" }}'
PARTITION_OPERATOR='{{ .partitionOperator | type "select" | description "Partition key operator" | options "=" "BETWEEN" "begins_with" | default "=" }}'
PARTITION_VALUE1='{{ .partitionValue1 | description "First value for partition key (or lower for BETWEEN)" | required "Value is required" }}'
PARTITION_VALUE2='{{ .partitionValue2 | description "Second value (only required for BETWEEN)" }}'

# -------- Sort Key (Optional) --------
SORT_KEY='{{ .sortKey | description "Sort key attribute name (optional)" }}'
SORT_OPERATOR='{{ .sortOperator | type "select" | options "=" "<" "<=" ">" ">=" "BETWEEN" "begins_with" | description "Sort key operator" }}'
SORT_VALUE1='{{ .sortValue1 | description "First sort key value (or lower for BETWEEN)" }}'
SORT_VALUE2='{{ .sortValue2 | description "Second sort key value (for BETWEEN only)" }}'

# -------- Optional Query Enhancements --------
FILTER_EXPR='{{ .filterExpression | description "Optional filter expression (e.g., rating >= :r)" }}'
PROJECTION_EXPR='{{ .projectionExpression | description "Comma-separated list of attributes to retrieve" }}'
SCAN_FORWARD='{{ .scanDirection | type "select" | options "true" "false" | default "false" | description "Sort order: true = ascending, false = descending" }}'
CONSISTENT_READ='{{ .consistentRead | type "select" | options "true" "false" | default "false" | description "Use strongly consistent read?" }}'
LIMIT='{{ .limit | description "Limit the number of items returned" }}'
START_KEY='{{ .startKey | description "ExclusiveStartKey JSON for pagination (optional)" }}'

# -------- Expression Names & Values --------
EXPR_ATTRIBUTE_NAMES="{\"#$PARTITION_KEY\": \"$PARTITION_KEY\""
EXPR_ATTRIBUTE_VALUES=""

KEY_CONDITION_EXPR=""

# Handle Partition Key
if [ "$PARTITION_OPERATOR" == "BETWEEN" ]; then
  KEY_CONDITION_EXPR="#$PARTITION_KEY BETWEEN :p1 AND :p2"
  EXPR_ATTRIBUTE_VALUES="{\":p1\": {\"S\": \"$PARTITION_VALUE1\"}, \":p2\": {\"S\": \"$PARTITION_VALUE2\"}}"
elif [ "$PARTITION_OPERATOR" == "begins_with" ]; then
  KEY_CONDITION_EXPR="begins_with(#$PARTITION_KEY, :p1)"
  EXPR_ATTRIBUTE_VALUES="{\":p1\": {\"S\": \"$PARTITION_VALUE1\"}}"
else
  KEY_CONDITION_EXPR="#$PARTITION_KEY $PARTITION_OPERATOR :p1"
  EXPR_ATTRIBUTE_VALUES="{\":p1\": {\"S\": \"$PARTITION_VALUE1\"}}"
fi

# Handle Sort Key (Optional)
if [ -n "$SORT_KEY" ]; then
  EXPR_ATTRIBUTE_NAMES+=", \"#$SORT_KEY\": \"$SORT_KEY\""
  if [ "$SORT_OPERATOR" == "BETWEEN" ]; then
    KEY_CONDITION_EXPR="$KEY_CONDITION_EXPR AND #$SORT_KEY BETWEEN :s1 AND :s2"
    EXPR_ATTRIBUTE_VALUES=$(echo "$EXPR_ATTRIBUTE_VALUES" | sed 's/}$//'),":s1": {\"S\": \"$SORT_VALUE1\"}, ":s2": {\"S\": \"$SORT_VALUE2\"}}'
  elif [ "$SORT_OPERATOR" == "begins_with" ]; then
    KEY_CONDITION_EXPR="$KEY_CONDITION_EXPR AND begins_with(#$SORT_KEY, :s1)"
    EXPR_ATTRIBUTE_VALUES=$(echo "$EXPR_ATTRIBUTE_VALUES" | sed 's/}$//'),":s1": {\"S\": \"$SORT_VALUE1\"}}'
  elif [ -n "$SORT_OPERATOR" ]; then
    KEY_CONDITION_EXPR="$KEY_CONDITION_EXPR AND #$SORT_KEY $SORT_OPERATOR :s1"
    EXPR_ATTRIBUTE_VALUES=$(echo "$EXPR_ATTRIBUTE_VALUES" | sed 's/}$//'),":s1": {\"S\": \"$SORT_VALUE1\"}}'
  fi
fi

EXPR_ATTRIBUTE_NAMES+="}"

# -------- Build Final Query --------
CMD="aws dynamodb query \
  --no-cli-pager \
  --no-cli-auto-prompt \
  --table-name \"$TABLE_NAME\""

if [ -n "$INDEX_NAME" ]; then
  CMD+=" --index-name \"$INDEX_NAME\""
fi

CMD+=" --key-condition-expression \"$KEY_CONDITION_EXPR\" \
  --expression-attribute-names '$EXPR_ATTRIBUTE_NAMES' \
  --expression-attribute-values '$EXPR_ATTRIBUTE_VALUES' \
  --scan-index-forward $SCAN_FORWARD \
  --consistent-read $CONSISTENT_READ"

if [ -n "$FILTER_EXPR" ]; then
  CMD+=" --filter-expression \"$FILTER_EXPR\""
fi

if [ -n "$PROJECTION_EXPR" ]; then
  CMD+=" --projection-expression \"$PROJECTION_EXPR\""
fi

if [ -n "$LIMIT" ]; then
  CMD+=" --limit $LIMIT"
fi

if [ -n "$START_KEY" ]; then
  CMD+=" --exclusive-start-key '$START_KEY'"
fi

# -------- Run the Command --------
echo "🔍 Running Query:"
echo "$CMD"
eval "$CMD"
