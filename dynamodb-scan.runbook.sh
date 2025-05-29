#!/bin/bash

# -------- Operation Type --------
OPERATION='{{ .operation | type "select" | description "Select operation type" | options "Scan" "Query" | default "Scan" }}'

# -------- Table Selection --------
TABLE_NAME='{{ .tableName | type "select" | description "Select a table or index" | options "Employee" "Movies" "Users" "Orders" | required "Table selection is required" }}'
INDEX_NAME='{{ .indexName | description "Optional: Specify an index name (leave blank for table scan)" }}'

# -------- Attribute Projection --------
PROJECTION_TYPE='{{ .projectionType | type "select" | description "Select attribute projection" | options "All attributes" "Specific attributes" | default "All attributes" }}'
PROJECTION_EXPR='{{ .projectionExpression | description "Comma-separated list of attributes (only if 'Specific attributes' selected)" }}'

# -------- Filters (Optional) --------
ENABLE_FILTER='{{ .enableFilter | type "select" | description "Add filters?" | options "No" "Yes" | default "No" }}'

# Filter 1
FILTER1_ATTRIBUTE='{{ .filter1Attribute | description "Filter 1: Attribute name" }}'
FILTER1_CONDITION='{{ .filter1Condition | type "select" | description "Filter 1: Condition" | options "Equal to" "Not equal to" "Less than" "Less than or equal to" "Greater than" "Greater than or equal to" "Between" "Begins with" "Contains" "Not contains" "Exists" "Not exists" | default "Equal to" }}'
FILTER1_TYPE='{{ .filter1Type | type "select" | description "Filter 1: Type" | options "String" "Number" "Binary" "Boolean" "Null" "List" "Map" | default "String" }}'
FILTER1_VALUE1='{{ .filter1Value1 | description "Filter 1: Value (or first value for BETWEEN)" }}'
FILTER1_VALUE2='{{ .filter1Value2 | description "Filter 1: Second value (only for BETWEEN)" }}'

# Additional Filters
ADD_MORE_FILTERS='{{ .addMoreFilters | type "select" | description "Add more filters?" | options "No" "Yes" | default "No" }}'

# Filter 2 (if enabled)
FILTER2_ATTRIBUTE='{{ .filter2Attribute | description "Filter 2: Attribute name" }}'
FILTER2_CONDITION='{{ .filter2Condition | type "select" | description "Filter 2: Condition" | options "Equal to" "Not equal to" "Less than" "Less than or equal to" "Greater than" "Greater than or equal to" "Between" "Begins with" "Contains" "Not contains" "Exists" "Not exists" | default "Equal to" }}'
FILTER2_TYPE='{{ .filter2Type | type "select" | description "Filter 2: Type" | options "String" "Number" "Binary" "Boolean" "Null" "List" "Map" | default "String" }}'
FILTER2_VALUE1='{{ .filter2Value1 | description "Filter 2: Value (or first value for BETWEEN)" }}'
FILTER2_VALUE2='{{ .filter2Value2 | description "Filter 2: Second value (only for BETWEEN)" }}'
FILTER_LOGIC='{{ .filterLogic | type "select" | description "Filter logic (if multiple filters)" | options "AND" "OR" | default "AND" }}'

# -------- Advanced Options --------
CONSISTENT_READ='{{ .consistentRead | type "select" | description "Use strongly consistent read?" | options "false" "true" | default "false" }}'
LIMIT='{{ .limit | description "Limit the number of items returned (optional)" }}'
TOTAL_SEGMENTS='{{ .totalSegments | description "Total segments for parallel scan (optional)" }}'
SEGMENT='{{ .segment | description "Segment number for parallel scan (optional)" }}'
START_KEY='{{ .startKey | description "ExclusiveStartKey JSON for pagination (optional)" }}'

# -------- Build the Command --------
if [ "$OPERATION" == "Scan" ]; then
    CMD="aws dynamodb scan"
else
    # This would require partition key inputs - not shown in the Scan UI
    echo "Query operation requires partition key configuration"
    exit 1
fi

CMD+=" --no-cli-pager --no-cli-auto-prompt --table-name \"$TABLE_NAME\""

# Add index if specified
if [ -n "$INDEX_NAME" ]; then
    CMD+=" --index-name \"$INDEX_NAME\""
fi

# Handle projection expression
if [ "$PROJECTION_TYPE" == "Specific attributes" ] && [ -n "$PROJECTION_EXPR" ]; then
    CMD+=" --projection-expression \"$PROJECTION_EXPR\""
fi

# Build filter expression if enabled
if [ "$ENABLE_FILTER" == "Yes" ] && [ -n "$FILTER1_ATTRIBUTE" ]; then
    FILTER_EXPR=""
    EXPR_ATTRIBUTE_NAMES="{"
    EXPR_ATTRIBUTE_VALUES="{"
    
    # Process Filter 1
    EXPR_ATTRIBUTE_NAMES+="\"#attr1\": \"$FILTER1_ATTRIBUTE\""
    
    # Convert condition to DynamoDB syntax
    case "$FILTER1_CONDITION" in
        "Equal to") FILTER_EXPR="#attr1 = :val1" ;;
        "Not equal to") FILTER_EXPR="#attr1 <> :val1" ;;
        "Less than") FILTER_EXPR="#attr1 < :val1" ;;
        "Less than or equal to") FILTER_EXPR="#attr1 <= :val1" ;;
        "Greater than") FILTER_EXPR="#attr1 > :val1" ;;
        "Greater than or equal to") FILTER_EXPR="#attr1 >= :val1" ;;
        "Between") FILTER_EXPR="#attr1 BETWEEN :val1 AND :val1b" ;;
        "Begins with") FILTER_EXPR="begins_with(#attr1, :val1)" ;;
        "Contains") FILTER_EXPR="contains(#attr1, :val1)" ;;
        "Not contains") FILTER_EXPR="NOT contains(#attr1, :val1)" ;;
        "Exists") FILTER_EXPR="attribute_exists(#attr1)" ;;
        "Not exists") FILTER_EXPR="attribute_not_exists(#attr1)" ;;
    esac
    
    # Add attribute value based on type (excluding Exists/Not exists)
    if [[ "$FILTER1_CONDITION" != "Exists" && "$FILTER1_CONDITION" != "Not exists" ]]; then
        case "$FILTER1_TYPE" in
            "String") EXPR_ATTRIBUTE_VALUES+="\": val1\": {\"S\": \"$FILTER1_VALUE1\"}" ;;
            "Number") EXPR_ATTRIBUTE_VALUES+="\": val1\": {\"N\": \"$FILTER1_VALUE1\"}" ;;
            "Boolean") EXPR_ATTRIBUTE_VALUES+="\": val1\": {\"BOOL\": $FILTER1_VALUE1}" ;;
            "Binary") EXPR_ATTRIBUTE_VALUES+="\": val1\": {\"B\": \"$FILTER1_VALUE1\"}" ;;
            "Null") EXPR_ATTRIBUTE_VALUES+="\": val1\": {\"NULL\": true}" ;;
        esac
        
        if [ "$FILTER1_CONDITION" == "Between" ] && [ -n "$FILTER1_VALUE2" ]; then
            case "$FILTER1_TYPE" in
                "String") EXPR_ATTRIBUTE_VALUES+=", \": val1b\": {\"S\": \"$FILTER1_VALUE2\"}" ;;
                "Number") EXPR_ATTRIBUTE_VALUES+=", \": val1b\": {\"N\": \"$FILTER1_VALUE2\"}" ;;
            esac
        fi
    fi
    
    # Process Filter 2 if enabled
    if [ "$ADD_MORE_FILTERS" == "Yes" ] && [ -n "$FILTER2_ATTRIBUTE" ]; then
        EXPR_ATTRIBUTE_NAMES+=", \"#attr2\": \"$FILTER2_ATTRIBUTE\""
        
        # Add logic operator
        FILTER_EXPR+=" $FILTER_LOGIC "
        
        # Convert condition to DynamoDB syntax
        case "$FILTER2_CONDITION" in
            "Equal to") FILTER_EXPR+="#attr2 = :val2" ;;
            "Not equal to") FILTER_EXPR+="#attr2 <> :val2" ;;
            "Less than") FILTER_EXPR+="#attr2 < :val2" ;;
            "Less than or equal to") FILTER_EXPR+="#attr2 <= :val2" ;;
            "Greater than") FILTER_EXPR+="#attr2 > :val2" ;;
            "Greater than or equal to") FILTER_EXPR+="#attr2 >= :val2" ;;
            "Between") FILTER_EXPR+="#attr2 BETWEEN :val2 AND :val2b" ;;
            "Begins with") FILTER_EXPR+="begins_with(#attr2, :val2)" ;;
            "Contains") FILTER_EXPR+="contains(#attr2, :val2)" ;;
            "Not contains") FILTER_EXPR+="NOT contains(#attr2, :val2)" ;;
            "Exists") FILTER_EXPR+="attribute_exists(#attr2)" ;;
            "Not exists") FILTER_EXPR+="attribute_not_exists(#attr2)" ;;
        esac
        
        # Add attribute value based on type (excluding Exists/Not exists)
        if [[ "$FILTER2_CONDITION" != "Exists" && "$FILTER2_CONDITION" != "Not exists" ]]; then
            EXPR_ATTRIBUTE_VALUES+=", "
            case "$FILTER2_TYPE" in
                "String") EXPR_ATTRIBUTE_VALUES+="\": val2\": {\"S\": \"$FILTER2_VALUE1\"}" ;;
                "Number") EXPR_ATTRIBUTE_VALUES+="\": val2\": {\"N\": \"$FILTER2_VALUE1\"}" ;;
                "Boolean") EXPR_ATTRIBUTE_VALUES+="\": val2\": {\"BOOL\": $FILTER2_VALUE1}" ;;
                "Binary") EXPR_ATTRIBUTE_VALUES+="\": val2\": {\"B\": \"$FILTER2_VALUE1\"}" ;;
                "Null") EXPR_ATTRIBUTE_VALUES+="\": val2\": {\"NULL\": true}" ;;
            esac
            
            if [ "$FILTER2_CONDITION" == "Between" ] && [ -n "$FILTER2_VALUE2" ]; then
                case "$FILTER2_TYPE" in
                    "String") EXPR_ATTRIBUTE_VALUES+=", \": val2b\": {\"S\": \"$FILTER2_VALUE2\"}" ;;
                    "Number") EXPR_ATTRIBUTE_VALUES+=", \": val2b\": {\"N\": \"$FILTER2_VALUE2\"}" ;;
                esac
            fi
        fi
    fi
    
    EXPR_ATTRIBUTE_NAMES+="}"
    EXPR_ATTRIBUTE_VALUES+="}"
    
    CMD+=" --filter-expression \"$FILTER_EXPR\""
    CMD+=" --expression-attribute-names '$EXPR_ATTRIBUTE_NAMES'"
    
    # Only add expression-attribute-values if we have values (not for Exists/Not exists)
    if [ "$EXPR_ATTRIBUTE_VALUES" != "{}" ]; then
        CMD+=" --expression-attribute-values '$EXPR_ATTRIBUTE_VALUES'"
    fi
fi

# Add consistent read option
CMD+=" --consistent-read $CONSISTENT_READ"

# Add optional parameters
if [ -n "$LIMIT" ]; then
    CMD+=" --limit $LIMIT"
fi

if [ -n "$TOTAL_SEGMENTS" ]; then
    CMD+=" --total-segments $TOTAL_SEGMENTS"
fi

if [ -n "$SEGMENT" ]; then
    CMD+=" --segment $SEGMENT"
fi

if [ -n "$START_KEY" ]; then
    CMD+=" --exclusive-start-key '$START_KEY'"
fi

# -------- Run the Command --------
echo "🔍 Running $OPERATION:"
echo "$CMD"
echo ""
eval "$CMD"
