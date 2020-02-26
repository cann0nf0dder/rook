#!/bin/bash
  while [[ "$#" -gt 0 ]]; do case $1 in
    --desired-rook-ver) rook_ver="$2"; shift;; ##Desired rook ver expected eg. 1.1.9 ##
    --current-rook-ver) rook_ver_current="$2"; shift;; ##Current rook ver expected eg. 1.1.2 ##
    --desired-ceph-ver) ceph_ver="$2"; shift;; ##Desired ceph ver expected eg. 14.2.7 ##
    --rook-image) rook_image="$2"; shift;; ##image URL##
    --ceph-image) ceph_image="$2"; shift;; ##image URL##
    *) echo "Unknown parameter passed: $1"; exit 1;;
esac; shift; done
# minor/patch level upgrades are detected automatically
minor=false

### Initialize ceph toolbox - Assumes that exist in your environment if not please deploy
TOOLS_POD=$(kubectl -n rook-ceph get pod -l "app=rook-ceph-tools" -o jsonpath='{.items[0].metadata.name}')

### Autodetect patch or minor upgrade ###
currentminor=${rook_ver_current:2:1}
desiredminor=${rook_ver:2:1}
if [[ $currentminor != $desiredminor ]]; then
  minor=true
fi

### Functions ###

rookcheck () {
  cephhealth=$(kubectl -n rook-ceph exec -i $TOOLS_POD ceph health)
  until [[ "$cephhealth" == *"HEALTH_OK"* ]]; do
      echo ""
      echo "Waiting for Rook Ceph to have HEALTH_OK status"
      sleep 5
      TOOLS_POD=$(kubectl -n rook-ceph get pod -l "app=rook-ceph-tools" -o jsonpath='{.items[0].metadata.name}')
      cephhealth=$(kubectl -n rook-ceph exec -i $TOOLS_POD ceph health)
      echo "Ceph health is currently:  $cephhealth"
      echo ""
  done
}

rookstatus () {
  TOOLS_POD=$(kubectl -n rook-ceph get pod -l "app=rook-ceph-tools" -o jsonpath='{.items[0].metadata.name}')
  echo "Display current PVs"
  kubectl get pv --all-namespaces
  echo ""
  echo "#############################################################"
  echo "Display current PVCs"
  kubectl get pvc --all-namespaces
  echo ""
  echo "#############################################################"
  echo "Display Rook status"
  echo "Rook status:"
  kubectl -n rook-ceph exec -it $TOOLS_POD -- ceph status
  echo "Display rook pods"
  kubectl -n rook-ceph get pods
  kubectl -n rook-ceph-system get pods
  sleep 10
}

### Display upgrade Summary

echo ""
echo ""
echo "This is a non-interactive upgrade, Please use CRTL+C to stop the script if needed"
echo ""
echo "#################################"
echo ""
echo "CURRENT ROOK VERSION: $rook_ver_current"
echo "TARGET ROOK VERSION: $rook_ver"
echo "Above versions information sourced from declarative data"
if [ "$minor" = true ]; then
  echo "INITIALIZING MINOR VERSION UPGRADE"
else
  echo "INITIALIZING PATCH VERSION UPGRADE"
fi
sleep 30

pre_minor_rook () {
  #### Required changes prior to upgrading rook (minor) ###
}

rookup () {
  #### Update Rook Image ####
  unset currentrook
  unset currentrook_ver_arr
  unset desiredrook_ver_arr
  #Obtain current images
  currentrook=$(kubectl -n rook-ceph get deployments -o jsonpath='{range .items[*]}{.metadata.labels.rook-version}{"\n"}{end}')
  #Declare current and desired images array
  currentrook_ver_arr=( $currentrook )
  desiredrook_ver_arr=( $currentrook )
  #Update desired array with desired ver
  arraylength=${#desiredrook_ver_arr[@]}
  for (( i=0; i<${arraylength}; i++ ));
    do
          desiredrook_ver_arr[$i]=v$rook_ver
    done
  #Compare running vs desired images
  if [[ "${currentrook_ver_arr[@]}" == "${desiredrook_ver_arr[@]}" ]]; then
    echo "rook deployment already at $rook_ver, skipping"
  else
    kubectl -n rook-ceph set image deploy/rook-ceph-operator rook-ceph-operator=$rook_image
      until [[ "${currentrook_ver_arr[@]}" == "${desiredrook_ver_arr[@]}" ]]; do
            echo "Waiting for deployment to update all pods"
            sleep 10
            currentrook=$(kubectl -n rook-ceph get deployments -o jsonpath='{range .items[*]}{.metadata.labels.rook-version}{"\n"}{end}')
            currentrook_ver_arr=( $currentrook )
      done
    echo "Deployment updated to $rook_ver"
    sleep 30
  fi
}

post_minor_rook () {
  #add changes if needed post rook upgrade
}

cephup () {
  ####  Upgrade Ceph ####
  unset currentceph
  unset currentceph_image_arr
  unset desiredceph_image_arr
  #Obtain current images
  currentceph=$(kubectl -n rook-ceph describe pods | grep "Image:.*/build-artifacts/sfmc-rook-ceph" | cut -d ':' -f 3)
  #Declare current and desired images array
  currentceph_image_arr=( $currentceph )
  desiredceph_image_arr=( $currentceph )
  #Update desired array with desired ver
  arraylength=${#desiredceph_image_arr[@]}
  for (( i=0; i<${arraylength}; i++ ));
    do
          desiredceph_image_arr[$i]=${ceph_image:15:20}
    done
  #Compare running vs desired images
  if [[ "${currentceph_image_arr[@]}" == "${desiredceph_image_arr[@]}" ]]; then
    echo "ceph version already at $ceph_ver, skipping"
  else
    kubectl -n rook-ceph patch CephCluster rook-ceph --type=merge -p "{\"spec\": {\"cephVersion\": {\"image\": \"$ceph_image\"}}}"
      until [[ "${currentceph_image_arr[@]}" == "${desiredceph_image_arr[@]}" ]]; do
            echo "Waiting for deployment to update all pods"
            sleep 10
            currentceph=$(kubectl -n rook-ceph describe pods | grep "Image:.*/build-artifacts/sfmc-rook-ceph" | cut -d ':' -f 3)
            currentceph_image_arr=( $currentceph )
      done
    echo "Ceph deployment updated to $ceph_ver"
    sleep 10
  fi
}

post_minor_ceph () {
      ### add changes for post ceph upgrade minor if needed
}

#####################################################################################################################

if [[ $minor = false ]];then
  rookcheck
  rookstatus
  rookosdcheck
  rookup
  rookcheck
  cephup
  rookstatus
else
  rookcheck
  rookstatus
  rookosdcheck
  pre_minor_rook
  pre_minor_ceph
  rookup
  post_minor_rook
  cephup
  post_minor_ceph
  rookstatus
fi
