#!/bin/bash
# set -ex
# set -x

# build script to build elasticsearch docker images

# TODO
#  - improve error detection

# Initialize vars
BUILD_VERS=""
config_file="build-list.cfg"
config_ok=0
repo="broadinstitute/mongo"

# flag to determine if new docker image should be built
build_docker=0

# set flags
FORCE_BUILD=${FORCE_BUILD:-0}

# Generic error outputting function
errorout() {
   if [ $1 -ne 0 ];
        then
        echo "${2}"
        exit $1
    fi
}

# check if config exists and has entries

if [ -f "${config_file}" ]
then
  # check if any valid entries in config file
  # valid entries have a valid alphanumeric valut in first column
  if  egrep -q "^[a-zA-Z0-9]+" ${config_file}
  then
     config_ok=1
  else
     errorout 1 "No valid entries in config file: ${config_file}"
  fi 
else
   errorout 1 "Missing build list config file: ${config_file}"
fi

# if config does not exist or has no entries to build see if
#  environment ES_VERSION have values


if [ "${FORCE_BUILD}" -ne 0 ]
then
   echo "FORCING BUILD of all versions"
fi

egrep "^[a-zA-Z0-9]+" ${config_file} | while read line
do
  # decode config line
  version=`echo $line | cut -d ':' -f1`

  # TODO maybe make config file more forgiving
  #  - support colon separated plugins,
  #  - supprot common separated plugins
  #  - support multiple separators common, colon, space

  # ensure Dockerfile does not exist
  rm -f Dockerfile

  # initialize flag for this version based on FORCE_BUILD value
  build_docker=${FORCE_BUILD}

  # Pull version from upstream repo
  docker pull ${repo}:${version}
  retcode=$?

  # if tag does not exist set build to true
  if [ "${retcode}" -ne 0 ]
  then
     build_docker=1
  fi

  if [ "${build_docker}" -eq 0 ]
  then
      echo "Skipping build of ${version} - not necessary"
      continue
  fi

  echo "Building version: ${version}"

  #  derive major version from version number
  major_version=`echo $version | cut -d '.' -f1,2`

  # use DOckerfile in major version dir as start
  if [ -f ${major_version}/Dockerfile ]
  then
     sed -e "s;MONGO_MAJOR_VERSION;${major_version};g" -e "s;MONGO_FULL_VERSION;${version};g" < ${major_version}/Dockerfile > Dockerfile
     
     # Add labels for certain information
     echo "LABEL GIT_BRANCH=${GIT_BRANCH}" >> Dockerfile
     echo "LABEL GIT_COMMIT=${GIT_COMMIT}" >> Dockerfile
     echo "LABEL BUILD_URL=${BUILD_URL}" >> Dockerfile

     # go ahead and put Dockerfile into image so you can see what it contained
     echo "ADD Dockerfile /" >> Dockerfile

     # grab entrypoint script
     if [ -f ${major_version}/docker-entrypoint.sh ]
     then
        cp ${major_version}/docker-entrypoint.sh .
     fi

     # run docker build
     docker build -t ${repo}:${version}_${BUILD_NUMBER} .
     retcode=$?
     errorout $retcode "ERROR: Build failed!"

     # if successful tag build as latest

     echo "tagging build as ${version}"
     docker tag ${repo}:${version}_${BUILD_NUMBER} ${repo}:${version}
     retcode=$?
     errorout $retcode "Build successful but could not tag it as latest"

     echo "Pushing images to dockerhub"
     docker push ${repo}:${version}_${BUILD_NUMBER} 
     retcode=$?
     errorout $retcode "Pushing new image to docker hub"

     docker push  ${repo}:${version}
     retcode=$?
     errorout $retcode "Pushing version tag image to docker hub"

     # clean up all built and pulled images

     cleancode=0
     echo "Cleaning up pulled and built images"
     docker rmi ${repo}:${version}_${BUILD_NUMBER}
     retcode=$?
     cleancode=$(($cleancode + $retcode))
     docker rmi ${repo}:${version}
     retcode=$?
     cleancode=$(($cleancode + $retcode))
     errorout $cleancode "Some images were not able to be cleaned up"
  else
     errorout 1 "Dockerfile for ${version} not found"
  fi
  # clean up tmp files
  rm -rf Dockerfile docker-entrypoint.sh

done


