export ZOSMF_URL="https://zzow03.zowe.marist.cloud"
export ZOSMF_PORT=10443
export ZOSMF_SYSTEM="S0W1"
export DIR="/u/zowead2"
export CSIHLQ="ZWE.PSWI.AZWE001"
export ZONE="TZONE"
export TMP_ZFS="ZOWEAD2.TMP.ZFS"
export ZOWE_ZFS="${CSIHLQ}.ZFS"
export ZOWE_MOUNT="/u/zwe/zowe-smpe/"
export VOLUME="ZOS003"
export TEST_HLQ="ZOWEAD2.PSWIT"
export VERSION="1.26.0"
export SYSAFF=2964 
export ACCOUNT=1

# Variables for workflows
# SMPE
export SMPMCS="ZOWEAD2"
export FMID="AZWE001"
export RFDSNPFX="ZOWE"
export CSIVOL="ZOS003"
export TZONE=$ZONE
# CSIHLQ for workflow is same as for PSWI
export DZONE="DZONE"
export THLQ="${CSIHLQ}.T"
export DHLQ="${CSIHLQ}.D"
export TVOL=$CSIVOL
export DVOL=$CSIVOL
export MOUNTPATH=$ZOWE_MOUNT
#PTF
export CSI=$CSIHLQ
export PTFDATASET="ZOWEAD2.ZOWE.AZWE001"
export TARGET=$TZONE
export DISTRIBUTION=$DZONE
export PTF1="UO01996"
export PTF2="UO01997"

export JOBNAME="ZWEPSWI1"
if [ -n "$ACCOUNT" ]
then
export JOBST1="//"${JOBNAME}" JOB ("${ACCOUNT}"),'PSWI',MSGCLASS=A,REGION=0M"
else
export JOBST1="//"${JOBNAME}" JOB 'PSWI',MSGCLASS=A,REGION=0M"
fi
export JOBST2="/*JOBPARM SYSAFF=${SYSAFF}"
export DEPLOY_NAME="DEPLOY"
export PSWI="zowe-PSWI"
export SWI_NAME=$PSWI
export TMP_MOUNT="${DIR}/zowe-tmp"
export TEST_MOUNT="${DIR}/test_mount"
export EXPORT="${TMP_MOUNT}/export/"
export WORK_MOUNT="${DIR}/work"
export WORK_ZFS="ZOWEAD2.WORK.ZFS"
export GLOBAL_ZONE=${CSIHLQ}.CSI
export EXPORT_DSN=${CSIHLQ}.EXPORT
export WORKFLOW_DSN=${CSIHLQ}.WORKFLOW
export ZOSMF_V="2.3"
export SMPE_WF_NAME="ZOWE_SMPE_WF"
export PTF_WF_NAME="ZOWE_PTF_WF"
export OUTPUT_ZFS="ZOWEAD2.OUTPUT.PSWI.ZFS"
export OUTPUT_MOUNT="/u/zowead2/PSWI"

echo "--------------------------------- Getting build specific variables ---------------------------------------"

find ~ -type f -name zowe-smpe\* -print

if [ -f pax/zowe-smpe.zip ]
then
  echo "ok"
  mkdir -p "unzipped"
  unzip pax/zowe-smpe.zip -d unzipped
else
  echo "zowe-smpe file not found"
  exit 255
fi

if [ -f unzipped/*.pax.Z ]
then
  echo "it's new fmid"
  export FMID=`ls unzipped | tail -n 1 | cut -f1 -d'.'`
  export RFDSNPFX=`cat unzipped/*htm | grep -o "hlq.*.${FMID}.F1" | cut -f2 -d'.'`
else
  echo "it's ptf/apar"
  #TODO: version could be obtained from the pipeline but last time I tried it it wasn't working
  export VERSION=`cat unzipped/*htm | grep -o "version.*," | grep -v "%" | cut -f2 -d' ' | cut -f1 -d','`
  mv unzipped/*htm ptfs.html
  NR=`ls unzipped | wc -l`
  
  if [ $NR -eq 2 ]
  then
    echo "standard situation"
    export RFDSNPFX=`ls unzipped | tail -n 1 | cut -f1 -d'.'`
    export FMID=`ls unzipped | tail -n 1 | cut -f2 -d'.'`
#    FILES=`ls unzipped`
#    IFS=$'\n'
#    for FILE in $FILES
#    do
#      PTF="`echo $FILE | tail -n 2 | cut -f3 -d'.'`\n"
#      export PTFS=$PTFS$PTF
#    done
    #TODO maybe I can read PTFs names from .htm file - from JCL I will still need in next shell script
    export PTFDATASET="${SMPMCS}.${RFDSNPFX}.${FMID}"
  else
    echo "Different number of files"
    #TODO:make it more universal (we have the workflow now just for two files anyway so change it with that)
  fi
fi

# workaround for now with hardcoded ptf names (datasets already prepared)
cd unzipped
HOST=${ZOSMF_URL#https:\/\/}

sshpass -p${ZOSMF_PASS} sftp -o BatchMode=no -o StrictHostKeyChecking=no -o PubkeyAuthentication=no -b - -P 22 ${ZOSMF_USER}@${HOST} << EOF
cd ..
cd ${SMPMCS}
put ${RFDSNPFX}.${FMID}.${PTF1}
put ${RFDSNPFX}.${FMID}.${PTF2}
EOF
cd ..

rm -r unzipped
echo "----------------------------------------------------------------------------------------------------------"

# Create SMP/E
sh 01_smpe.sh # last time didnt delete smpe - testing
smpe=$?

if [ $smpe -eq 0 ];then
# Apply PTFs
sh 02_ptf.sh
ptf=$?

if [ $ptf -eq 0 ];then
# Create PSWI
sh 03_create.sh
create=$?

# Cleanup after the creation of PSWI
sh 04_create_cleanup.sh

if [ $create -eq 0 ];then 
# Test PSWI
sh 05_test.sh
test=$?

# Cleanup after the test
sh 06_test_cleanup.sh
fi 
fi 
fi

# Cleanup of SMP/E
sh 07_smpe_cleanup.sh

echo ""
echo ""

if [ $smpe -ne 0 ] || [ $ptf -ne 0 ] || [ $create -ne 0 ] || [ $test -ne 0 ]
then
  echo "Build unsuccessful!"
  if [ $smpe -ne 0 ]; then
    echo "SMP/E wasn't successful."
  elif [ $ptf -ne 0 ]; then
    echo "Applying PTFs wasn't successful."
  elif [ $create -ne 0 ]; then
    echo "Creation of PSWI wasn't successful."
  elif [ $test -ne 0 ]; then
    echo "Testing of PSWI wasn't successful."
  fi
  exit -1
else
  echo "Build successful!"
  exit 0
fi
