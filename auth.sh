loadsecret() {
    which jq >/dev/null || (echo "Please install jq"; exit 1)
    if [[ ! -f client.json ]]; then
        echo "Download JSON with oauth credentials into 'client.json'"
        exit 1
    fi
    eval $(jq -r '.installed | to_entries | map("_secret_\(.key)=" + @sh "\(.value|tostring)")|.[]' client.json)
    _secret_project_number=${_secret_client_id/-*}
}

oauth() {
    ###
    ### Used https://stackoverflow.com/a/18260206 as a base
    ###

    APP_NAME=${APP_NAME:-${_secret_project_id:?}}
    APP_SCOPE=${APP_SCOPE:?}

    # create your own client id/secret
    # https://developers.google.com/identity/protocols/OAuth2InstalledApp#creatingcred
    client_id=${_secret_client_id:?}
    client_secret=${_secret_client_secret:?}
    auth_uri=${_secret_auth_uri:-"https://accounts.google.com/o/oauth2/v2/auth"}
    token_uri=${_secret_token_uri:-"https://www.googleapis.com/oauth2/v4/token"}

    # Store our credentials in our home directory with a file called .
    my_creds=~/.oauth2-$APP_NAME

    if [ -s $my_creds ]; then
      # if we already have a token stored, use it
      . $my_creds
      time_now=`date +%s`
    else
      scope=$APP_SCOPE
      # Form the request URL
      # https://developers.google.com/identity/protocols/OAuth2InstalledApp#step-2-send-a-request-to-googles-oauth-20-server
      auth_url="$auth_uri?client_id=$client_id&scope=$scope&response_type=code&redirect_uri=urn:ietf:wg:oauth:2.0:oob"

      echo "Please go to:"
      echo
      echo "$auth_url"
      echo
      echo "after accepting, enter the code you are given:"
      read auth_code

      # exchange authorization code for access and refresh tokens
      # https://developers.google.com/identity/protocols/OAuth2InstalledApp#exchange-authorization-code
      auth_result=$(curl -s $token_uri \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d code=$auth_code \
        -d client_id=$client_id \
        -d client_secret=$client_secret \
        -d redirect_uri=urn:ietf:wg:oauth:2.0:oob \
        -d grant_type=authorization_code)
      access_token=$(echo -e "$auth_result" | \
                     grep -Po '"access_token" *: *.*?[^\\]",' | \
                     awk -F'"' '{ print $4 }')
      refresh_token=$(echo -e "$auth_result" | \
                      grep -Po '"refresh_token" *: *.*?[^\\]",*' | \
                      awk -F'"' '{ print $4 }')
      expires_in=$(echo -e "$auth_result" | \
                   grep -Po '"expires_in" *: *.*' | \
                   awk -F' ' '{ print $3 }' | awk -F',' '{ print $1}')
      time_now=`date +%s`
      expires_at=$((time_now + expires_in - 60))
      echo -e "access_token=$access_token\nrefresh_token=$refresh_token\nexpires_at=$expires_at" > $my_creds
    fi

    # if our access token is expired, use the refresh token to get a new one
    # https://developers.google.com/identity/protocols/OAuth2InstalledApp#offline
    if [ $time_now -gt $expires_at ]; then
      refresh_result=$(curl -s $token_uri \
       -H "Content-Type: application/x-www-form-urlencoded" \
       -d refresh_token=$refresh_token \
       -d client_id=$client_id \
       -d client_secret=$client_secret \
       -d grant_type=refresh_token)
      access_token=$(echo -e "$refresh_result" | \
                     grep -Po '"access_token" *: *.*?[^\\]",' | \
                     awk -F'"' '{ print $4 }')
      expires_in=$(echo -e "$refresh_result" | \
                   grep -Po '"expires_in" *: *.*' | \
                   awk -F' ' '{ print $3 }' | awk -F',' '{ print $1 }')
      time_now=`date +%s`
      expires_at=$(($time_now + $expires_in - 60))
      echo -e "access_token=$access_token\nrefresh_token=$refresh_token\nexpires_at=$expires_at" > $my_creds
    fi

    echo $access_token
}

if false; then
    # call the Directory API list users endpoint, may be multiple pages
    # https://developers.google.com/admin-sdk/directory/v1/reference/users/list
    while :
    do
      api_data=$(curl -s --get https://www.googleapis.com/admin/directory/v1/users \
        -d customer=my_customer \
        -d prettyPrint=true \
        `if [ -n "$next_page" ]; then echo "-d pageToken=$next_page"; fi` \
        -d maxResults=500 \
        -d "fields=users(primaryEmail,creationTime,lastLoginTime),nextPageToken" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $access_token")
      echo -e "$api_data" | grep -v 'nextPageToken'
      next_page=$(echo $api_data | \
        grep -Po '"nextPageToken" *: *.*?[^\\]"' | \
        awk -F'"' '{ print $4 }')
      if [ -z "$next_page" ]
      then
        break
      fi
    done
fi

