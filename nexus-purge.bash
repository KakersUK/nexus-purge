#!/bin/bash
# Purge Nexus
# Copyright (C) 2024 Sébastien Picavet
# Copyright (C) 2025 Jamie Scott
#
# This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 2 of the License.
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with this program.  If not, see <https://www.gnu.org/licenses/>.

authCreds=''
baseURL='http://127.0.0.1:8080'
reposToMaintain=('release')
maxVersionCount=3
CURL_OPTS='--silent'

while getopts ':dv' opt; do
  case $opt in
    d)
      dryRun=true
      ;;
    v)
      CURL_OPTS='--verbose'
      VERBOSE=true
      ;;
    *)
      echo
      echo "Usage: $(basename "${0}") [-dv]"
      echo "options:"
      echo "d    Dry run"
      echo "v    verbose output"
      echo
      exit 1
      ;;
  esac
done

# Loop through each repository
for repoName in ${reposToMaintain[@]}
do

  [ "${VERBOSE}" ] && echo 'Calling Nexus...'
  jsonResponse=$(curl ${CURL_OPTS} --user "${authCreds}" "${baseURL}/service/rest/v1/components?repository=${repoName}")
  tokenNext=$(echo "${jsonResponse}" | jq --raw-output '.continuationToken // empty')
  [ "${VERBOSE}" ] && echo "Next token: ${tokenNext}"

  # Closing, you must read everything because the order is not guaranteed
  while [ "${tokenNext}" != "" ]
  do
    [ "${VERBOSE}" ] && echo 'New iteration'

    jsonResponseNext=$(curl ${CURL_OPTS} --user "${authCreds}" "${baseURL}/service/rest/v1/components?repository=${repoName}&continuationToken=${tokenNext}")
    tokenNext=$(echo "${jsonResponseNext}" | jq --raw-output '.continuationToken // empty')

    # Concatenate all
    jsonResponse="${jsonResponse}${jsonResponseNext}"

    [ "${VERBOSE}" ] && echo "Next token? ${tokenNext}"
  done

  # Extracting the information we need and grouping by component ; hack to have a line per couple in order to count and shell a little
  for componentArray in $(echo "${jsonResponse}" | jq '.items[] | {component: .name, version: .version, id: .id}' | jq --slurp --compact-output 'group_by(.component)' | sed 's/\],\[/\]\n\[/g' | sed 's/\[\[/\[/' | sed 's/\]\]/\]/')
  do
    # More than X versions of a component?
    if [ $(echo "${componentArray}" | jq 'length') -gt ${maxVersionCount} ]
    then
      [ "${VERBOSE}" ] && echo "More than ${maxVersionCount} versions: $(echo ${componentArray} | jq)"

      # Sort versions and exclude last X lines
      for versionArray in $(echo "${componentArray}" | jq --raw-output '.[].version' | sort --version-sort | head --lines -${maxVersionCount})
      do
        conponentName=$(echo "${componentArray}" | jq --raw-output '.[0].component')
        componentID=$(echo "${componentArray}" | jq --raw-output '.[] | select(.version == "'${versionArray}'") | .id')
        [ "${VERBOSE}" ] && echo "Deleting version ${versionArray} (id: ${assetID}) of component ${conponentName} from ${repoName}"

        # Dry run will simulate the curl command
        if [ ${dryRun} ]
        then
          echo "curl ${CURL_OPTS} --request DELETE --user ${authCreds}" "${baseURL}/service/rest/v1/components/${componentID}"
        else
          curl ${CURL_OPTS} --request DELETE --user "${authCreds}" "${baseURL}/service/rest/v1/components/${componentID}"
        fi

      done
    fi
  done
done
