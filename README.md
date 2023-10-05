# "Gluck"

Gluckose data uploader from Abbott's LibreView into Google Fit.

Simple quick hack to upload output from libreview.com into GoogleFit.

# Function

This script transfers:

- Continuous Glucose history (Record Type=0), which is 1 data point per 5 minutes;
- Notes entries in hope that it is food you ate, as food entries without corresponding calories etc.

Notes:
- The CSV file doesn't contain the meal type you set in UI. Dunno why :(
- The "Excercise" is logged as two entries with record type 6 at the same second,
  where one says "Excercise" (in language of setting, so CSV must be in English)
  and another one contain your note message if any. Script ignores these both lines.

As of today, GoogleFit app shows Glucose graphs with these data, but raw food inserted for some
reason is not visible in the UI -- but it is available in the data though, so the analysis is still
possible.

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

- `apt install jq curl`

## Configure libreview.com

- Log into libreview.com
- Go to "sandwich" in right-top corner, Account Settings, Preferences
- Script works for mmol/L units only
- Set Year-Month-Day date format, 24 hours time format
- Choose English language (required to make sure Excercise skipping working)

## Adjust Timezone

Change in `gluck.sh` value at `CSVTZ` from +2 to your local timezone.
Yes, there would be problems around DST change, I know.

# Usage

- Log into libreview.com
- Use "Download Glucose Data" button to download data
- run `./gluck.sh /path/to/YourName_glucose_date.csv`

Viel Glück!
