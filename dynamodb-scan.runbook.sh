#!/bin/bash

# -------- Filters - optional --------
FILTER_VALUE='{{ .filterValue | description "Enter attribute value" }}'
FILTER_TYPE='{{ .filterType | type "select" | description "Type" | options "String" | default "String" }}'
FILTER_CONDITION='{{ .filterCondition | type "select" | description "Condition" | options "Equal to" "Not equal to" "Less than or equal to" "Less than" "Greater than or equal to" "Greater than" "Between" "Exists" "Not exists" "Contains" "Not contains" "Begins with" | default "Equal to" }}'
FILTER_ATTRIBUTE='{{ .filterAttribute | description "Attribute name" }}'

# -------- Select a table or index --------
TABLE_NAME='{{ .tableName | type "select" | description "Select a table or index" | options "Table - Employee" | default "Table - Employee" }}'

# -------- Build and Run Command --------
CMD="aws dynamodb scan --table-name Employee"

# Add filter if provided
if [ -n "$FILTER_ATTRIBUTE" ] && [ -n "$FILTER_VALUE" ]; then
    case "$FILTER_CONDITION" in
        "Equal to")
            CMD+=" --filter-expression \"#attr = :val\""
            CMD+=" --expression-attribute-names '{\"#attr\": \"$FILTER_ATTRIBUTE\"}'"
            CMD+=" --expression-attribute-values '{\":val\": {\"S\": \"$FILTER_VALUE\"}}'"
            ;;
        "Not equal to")
            CMD+=" --filter-expression \"#attr <> :val\""
            CMD+=" --expression-attribute-names '{\"#attr\": \"$FILTER_ATTRIBUTE\"}'"
            CMD+=" --expression-attribute-values '{\":val\": {\"S\": \"$FILTER_VALUE\"}}'"
            ;;
        "Less than")
            CMD+=" --filter-expression \"#attr < :val\""
            CMD+=" --expression-attribute-names '{\"#attr\": \"$FILTER_ATTRIBUTE\"}'"
            CMD+=" --expression-attribute-values '{\":val\": {\"S\": \"$FILTER_VALUE\"}}'"
            ;;
        "Less than or equal to")
            CMD+=" --filter-expression \"#attr <= :val\""
            CMD+=" --expression-attribute-names '{\"#attr\": \"$FILTER_ATTRIBUTE\"}'"
            CMD+=" --expression-attribute-values '{\":val\": {\"S\": \"$FILTER_VALUE\"}}'"
            ;;
        "Greater than")
            CMD+=" --filter-expression \"#attr > :val\""
            CMD+=" --expression-attribute-names '{\"#attr\": \"$FILTER_ATTRIBUTE\"}'"
            CMD+=" --expression-attribute-values '{\":val\": {\"S\": \"$FILTER_VALUE\"}}'"
            ;;
        "Greater than or equal to")
            CMD+=" --filter-expression \"#attr >= :val\""
            CMD+=" --expression-attribute-names '{\"#attr\": \"$FILTER_ATTRIBUTE\"}'"
            CMD+=" --expression-attribute-values '{\":val\": {\"S\": \"$FILTER_VALUE\"}}'"
            ;;
        "Between")
            # For Between, we'd need a second value field
            CMD+=" --filter-expression \"#attr BETWEEN :val1 AND :val2\""
            CMD+=" --expression-attribute-names '{\"#attr\": \"$FILTER_ATTRIBUTE\"}'"
            CMD+=" --expression-attribute-values '{\":val1\": {\"S\": \"$FILTER_VALUE\"}, \":val2\": {\"S\": \"$FILTER_VALUE\"}}'"
            ;;
        "Exists")
            CMD+=" --filter-expression \"attribute_exists(#attr)\""
            CMD+=" --expression-attribute-names '{\"#attr\": \"$FILTER_ATTRIBUTE\"}'"
            ;;
        "Not exists")
            CMD+=" --filter-expression \"attribute_not_exists(#attr)\""
            CMD+=" --expression-attribute-names '{\"#attr\": \"$FILTER_ATTRIBUTE\"}'"
            ;;
        "Contains")
            CMD+=" --filter-expression \"contains(#attr, :val)\""
            CMD+=" --expression-attribute-names '{\"#attr\": \"$FILTER_ATTRIBUTE\"}'"
            CMD+=" --expression-attribute-values '{\":val\": {\"S\": \"$FILTER_VALUE\"}}'"
            ;;
        "Not contains")
            CMD+=" --filter-expression \"NOT contains(#attr, :val)\""
            CMD+=" --expression-attribute-names '{\"#attr\": \"$FILTER_ATTRIBUTE\"}'"
            CMD+=" --expression-attribute-values '{\":val\": {\"S\": \"$FILTER_VALUE\"}}'"
            ;;
        "Begins with")
            CMD+=" --filter-expression \"begins_with(#attr, :val)\""
            CMD+=" --expression-attribute-names '{\"#attr\": \"$FILTER_ATTRIBUTE\"}'"
            CMD+=" --expression-attribute-values '{\":val\": {\"S\": \"$FILTER_VALUE\"}}'"
            ;;
    esac
fi

# Run the command
echo "🔍 Running Scan on Employee table:"
echo "$CMD"
echo ""
eval "$CMD"
