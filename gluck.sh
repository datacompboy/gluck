#!/bin/bash
. auth.sh

# Timezone for timestamps in CSV
CSVTZ="+2" 

if [[ -z "$1" || ! -f "$1" ]]; then
    echo "Use: $0 YourLog.csv"
    exit 1
fi
INPUT=$1

APP_SCOPE=""
DEL=""
for scope in blood_glucose nutrition; do
    APP_SCOPE="${APP_SCOPE}${DEL}https://www.googleapis.com/auth/fitness.$scope.read"
    DEL="+"
    APP_SCOPE="${APP_SCOPE}${DEL}https://www.googleapis.com/auth/fitness.$scope.write"
done
loadsecret
AUTH=$(oauth)

createds() {
    local DATATYPE=$1
    local DATASOURCE="raw:$DATATYPE:$_secret_project_number:Gluck"
    #curl -X DELETE -H "Authorization: Bearer $AUTH" https://www.googleapis.com/fitness/v1/users/me/dataSources/$DATASOURCE
    curl -s -H "Authorization: Bearer $AUTH" https://www.googleapis.com/fitness/v1/users/me/dataSources | grep $DATASOURCE > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        read -r -d '' DATASOURCE << EOM
{
  "dataStreamId": "$DATASOURCE",
  "dataStreamName": "Gluck",
  "type": "raw",
  "application": {
    "detailsUrl": "https://datacompboy.dev/p/gluck",
    "name": "Gluck",
    "version": "1"
  },
  "dataType": {
    "name": "$DATATYPE"
   }
}
EOM
        curl -s -H "Authorization: Bearer $AUTH" -H "Content-Type: application/json;encoding=utf-8" --data-raw "$DATASOURCE" \
            https://www.googleapis.com/fitness/v1/users/me/dataSources | jq -r ".dataStreamId"
    else
        echo $DATASOURCE
    fi
}
createds_glucose() {
    createds "com.google.blood_glucose"
}
createds_food() {
    createds "com.google.nutrition"
}

GLUSRC=$(createds_glucose)
FOOSRC=$(createds_food)

format_glu() {
    local TSNS=$1
    local VAL=$2
    echo '{"startTimeNanos":'$TSNS',"endTimeNanos":'$TSNS',"dataTypeName":"com.google.blood_glucose","value":[{"fpVal":'$VAL'},{},{},{},{}]}'
}
format_food() {
    local TSNS=$1
    local VAL
    printf -v VAL "%q" "$2"
    echo '{"startTimeNanos":'$TSNS',"endTimeNanos":'$TSNS',"dataTypeName":"com.google.nutrition","value":[{"mapVal":[{}]},{},{"stringVal":"'$VAL'"}]}'
}

replaceday() {
    local DS=$1
    local DAY=$2
    local MINTS=$3
    local POINTS=$4
    local MODE=$5
    local DAY0="$(date -d "$DAY 00:00:00 UTC" -u "+%s")000000000"
    local DAYE="$(date -d "$DAY 23:59:59 UTC" -u "+%s")999999999"
    if [[ -z $MODE ]]; then
        if [[ $(( MINTS - DAY0 )) -gt $(( 10 * 60 * 1000 * 1000 * 1000 )) ]]; then
            MODE="Partial"
            DAY0=$MINTS
        else
            MODE="Full"
        fi
    else
        MODE="Full"
    fi
    echo "$MODE $DAY: $DAY0..$DAYE..."

    local DATA='{"minStartTimeNs":'$DAY0',"maxEndTimeNs":'$DAYE',"dataSourceId":"'$DS'","point":'$POINTS'}'
    local DATASET="https://www.googleapis.com/fitness/v1/users/me/dataSources/$DS/datasets/$DAY0-$DAYE"
    curl -s -X DELETE -H "Authorization: Bearer $AUTH" "$DATASET" | grep -A 10 '"error"'
    curl -s -X PATCH -H "Authorization: Bearer $AUTH" -H "Content-Type: application/json;encoding=utf-8"  --data-raw "$DATA" "$DATASET" | grep -A 10 '"error"'
}

ODATE=""
DATA=""
OK=""

handle_line() {
    local INTS=$1
    local RT=$2
    local VAL=$3
    local FOOD=$4

    DATE=$(date -d "$INTS $CSVTZ" -u "+%F")
    TSNS="$(date -d "$INTS $CSVTZ" -u "+%s")000000000"
    if [[ "$DATE" != "$ODATE" ]]; then
        if [[ -n "$DATA" ]]; then
            replaceday $DS $ODATE $MINTS "$DATA]" $MODE
        fi
        ODATE=$DATE
        MINTS=$TSNS
        DATA=""
        DEL="["
        MODE=""
    fi

    # 5min measurements
    if [[ $RT == "0" ]]; then
        DS=$GLUSRC
        MODE=""
        DATA="$DATA$DEL$(format_glu "$TSNS" "$VAL")"
        DEL=","
    fi
    # 1 = look-at-data points
    # 6 = comments
    if [[ $RT == "6" ]]; then
        DS=$FOOSRC
        DATA="$DATA$DEL$(format_food "$TSNS" "$FOOD")"
        DEL=","
        MODE="Full"
    fi
}

PINTS=""
while IFS="," read -r _ _ INTS RT VAL _ _ _ _ _ _ _ _ FOOD; do
    if [[ -z "$OK" ]]; then
        if [[ "$VAL" != "Historic Glucose mmol/L" ]]; then
            echo "Please set English in libreview.com profile settings and download new csv"
            echo "'$VAL' should be equals to 'Historic Glucose mmol/L'"
            exit 1
        fi
        OK="ok"
        continue
    fi
    FOOD=${FOOD%%,,,,,*}
    if [[ -n $PINTS ]]; then
        # Suppress Excercise lines and optional same-second comment
        if [[ "$PINTS" == "$INTS" && ( "$FOOD" == "Exercise" || "$PFOOD" == "Exercise" ) ]]; then
            # Skip both lines
            PINTS=""
            continue
        fi
        # Skip Exercise line if it's alone
        if [[ "$PFOOD" != "Exercise" ]]; then
            handle_line "$PINTS" "$PRT" "$PVAL" "$PFOOD"
        fi
    fi
    PINTS=$INTS
    PRT=$RT
    PVAL=$VAL
    PFOOD=$FOOD
done < <(tail -n +2 $INPUT)
if [[ -n "$PINTS" && "$PFOOD" != "Exercise" ]]; then
    handle_line "$PINTS" "$PRT" "$PVAL" "$PFOOD"
fi
if [[ -n $DATA ]]; then
    replaceday $DS $DATE $MINTS "$DATA]" $MODE
fi

