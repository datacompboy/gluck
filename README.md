# "Gluck"

Gluckose data uploader from Abbott's LibreView into Google Fit.

Simple quick hack to upload output from libreview.com into GoogleFit.

# Preparation

## Create Google App

- Create Google App
- Add fitness API, enable permissions for
   - `https://www.googleapis.com/auth/fitness.blood_glucose.read`
   - `https://www.googleapis.com/auth/fitness.blood_glucose.write`
   - `https://www.googleapis.com/auth/fitness.nutrition.read`
   - `https://www.googleapis.com/auth/fitness.nutrition.write`
- Create OAuth credentials, download as `client.json` file.

## Install dependencies

- `apt get install jq curl`

## Configure libreview.com

- Log into libreview.com
- Go to "sandwich" in right-top corner, Account Settings, Preferences
- Script works for mmol/L units only
- Set Year-Month-Day date format, 24 hours time format

## Adjust Timezone

Change in `gluck.sh` value at `CSVTZ` from +2 to your local timezone.
Yes, there would be problems around DST change, I know.

# Usage

- Log into libreview.com
- Use "Download Glucose Data" button to download data
- run `./gluck.sh /path/to/YourName_glucose_date.csv`

Viel Glück!
