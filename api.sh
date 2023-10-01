#!/bin/bash
export bearer_token=BEARER_TOKEN
export quay_registry=QUAY_REGISTRY
#export orga=ORGANIZATION_NAME
#export repo=REPOSITORY_NAME
#export tag=TAG
#export newtag=NEWTAG
#export manifest_digest=MANIFEST_DIGEST
#export team=TEAM_NAME
#export user=USER_NAME
#export robot=ROBOT_SHORT_NAME
export allorgs=(myorg exorg quay aorg borg corg)

# List orgs
ORGS=$(curl -s -X GET -H "Authorization: Bearer ${bearer_token}" https://${quay_registry}/api/v1/superuser/organizations/ | jq -r '.organizations [] .name')

# Makes sure that allorgs exist
missingorg=""
for checkorg in ${allorgs[@]}; do
  exists=0
  for existorg in $ORGS; do
    if [[ "$existorg" == "$checkorg" ]]; then
      exists=1
    fi
  done
  if [ $exists -ne 1 ]; then
    missingorg="$missingorg,$checkorg"
  fi
done
missingorg=$(echo $missingorg | sed 's/^,//' | tr ',' ' ')

if [[ ! -z $missingorg ]]; then
  for missing in $missingorg; do
    echo -n "Organisation $missing "
    curl -s -X POST -H "Authorization: Bearer ${bearer_token}" -H "Content-Type: application/json" --data "{\"name\": \"${missing}\"}" https://${quay_registry}/api/v1/organization/ | jq -r
  done
fi


# List repositories & tags in org
for currentorg in $ORGS; do
  echo "Current org = $currentorg"
  repos=$(curl -s -X GET -H "Authorization: Bearer ${bearer_token}" https://${quay_registry}/api/v1/repository?namespace=${currentorg} | jq -r '.repositories [] .name')
  if [[ -z $repos ]]; then
    echo -e "\t No repositories in $currentorg"
  fi
  for repo in $repos; do
    echo "Current repository = $repo"
#   curl -s -X GET -H "Authorization: Bearer ${bearer_token}" https://${quay_registry}/api/v1/repository/${currentorg}/${repo}/tag/ | jq
    curl -s -X GET -H "Authorization: Bearer ${bearer_token}" https://${quay_registry}/api/v1/repository/${currentorg}/${repo}/tag/ | jq -r '.tags [] | "\(.last_modified):\(.name)"' | sort -h -r -t ':' -k 1
  done
done


# Gets tags >3 for a repository and adds expiation date

# For each organisation
for currentorg in $ORGS; do
  echo "Current org = $currentorg"

  # For each repo
  repos=$(curl -s -X GET -H "Authorization: Bearer ${bearer_token}" https://${quay_registry}/api/v1/repository?namespace=${currentorg} | jq -r '.repositories [] .name')
  for repo in $repos; do

    # Gets all the tags, sorts them by modified date and outputs the tag of all but the most recent 3
    echo "Current repository = $repo"
    exptags=$(curl -s -X GET -H "Authorization: Bearer ${bearer_token}" https://${quay_registry}/api/v1/repository/${currentorg}/${repo}/tag/ | jq -r '.tags [] | "\(.last_modified)~\(.name)"' | sort -h -r -t '~' -k 1 | tail -n +4 | cut -d '~' -f 2)

    # For each of the tags found
    for exptag in $exptags; do
      echo "EXPTAG=$exptag"

      # Checks to see if the tag has an expirey date already
      hasexp=$(curl -s -X GET -H "Authorization: Bearer ${bearer_token}" https://${quay_registry}/api/v1/repository/${currentorg}/${repo}/tag/ | jq ".tags [] | select (.name==\"$exptag\") .expiration")
      echo "HASEXP=$hasexp"

      # If it has an expirey date doesn't do anything, otherwise adds a date 14 days from now
      if [[ $hasexp == null ]]; then
        echo "NEEDS EXP"
        expdate=$(date -d "+14 days" +%s)
        echo "EXPDATE=$expdate"
        curl -s -X PUT -H "Authorization: Bearer ${bearer_token}" -H "Content-Type: application/json" -d "{\"expiration\": $expdate}" https://${quay_registry}/api/v1/repository/${currentorg}/${repo}/tag/${exptag} | jq
      fi
    done
  done
done
