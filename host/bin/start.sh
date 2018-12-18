#!/bin/bash

if [[ $UID != 0 ]]; then
    echo "Please run this script with sudo:"
    echo "sudo $0 $*"
    exit 1
fi

cpu=`uname -m`

if [ -z "$HOME" ] || [ "$HOME" == "/" ]; then
  HOME=~root
fi
DEFAULT_REPO="u3ds1991/Photonic3D"
#DEFAULT_REPO="area515/Creation-Workshop-Host"
CONFIG_PROPS="${HOME}/3dPrinters/config.properties"

echo "Local Config: $CONFIG_PROPS"

if [ -f ${CONFIG_PROPS} ]; then
  CONFIG_REPO=$(grep '^updateRepo' "${CONFIG_PROPS}" | cut -d= -f 2 | awk '$1=$1')
  if [[ ${CONFIG_REPO} ]]; then
    DEFAULT_REPO="${CONFIG_REPO}"
  fi
fi

if [ -z "$1" ]; then
	repo=${DEFAULT_REPO}
else
	if [[ $1 =~ .*Creation-Workshop-Host.* ]] || [[ $1 =~ .*Photonic3D.* ]]; then
		repo=$1
	else
		repo="$1/Creation-Workshop-Host"
	fi;
fi;

if [ "$2" == "TestKit" ]; then
	downloadPrefix=cwh$2-
	installDirectory=/opt/cwh$2
else
	downloadPrefix=cwh-
	installDirectory=/opt/cwh
fi;


#This application will always need to have the display set to the following
export DISPLAY=:0.0
xinitProcess=`ps -ef | grep grep -v | grep xinit`
if [ -z "${xinitProcess}" ]; then
    echo No X server running, starting and configuring one
    startx &
    xhost +x
fi

#Copy the zip file from the current directory into the cwh directory for offline install
mkdir -p ${installDirectory}
mv ${downloadPrefix}.*.zip ${installDirectory}

#install java if version is too old
javaInstalled=`which java`
if [ "$javaInstalled" = "" ]; then
	javaMajorVersion=0
	javaMinorVersion=0
else
	javaMajorVersion=`java -version 2>&1 | grep "java version" | awk -F[\".] '{print "0"$2}'`
	javaMinorVersion=`java -version 2>&1 | grep "java version" | awk -F[\".] '{print "0"$3}'`
fi

if [ "$javaMinorVersion" -lt 8 -a "$javaMajorVersion" -le 1 ]; then
	apt install openjdk-8-jdk -y
fi

#Determine if a new install is available
echo Checking for new version from Github Repo: ${repo}
cd ${installDirectory}
LOCAL_TAG=$(grep repo.version build.number | cut -d = -f 2 | tr -d '\r')
NETWORK_TAG=$(curl -L -s https://api.github.com/repos/${repo}/releases/latest | grep 'tag_name' | cut -d\" -f4)

echo Local Tag: ${LOCAL_TAG}
echo Network Tag: ${NETWORK_TAG}

if [ -f ${downloadPrefix}.*.zip ]; then
	OFFLINE_FILE=$(ls ${downloadPrefix}.*.zip)
	echo Performing offline install of ${OFFLINE_FILE}

	mv ${OFFLINE_FILE} ~
	rm -r ${installDirectory}
	mkdir -p ${installDirectory}
	cd ${installDirectory}
	mv ~/${OFFLINE_FILE} .
	unzip ${OFFLINE_FILE}
	chmod 777 *.sh
	rm ${OFFLINE_FILE}
elif [ -z "${NETWORK_TAG}" ]; then
	echo "Couldn't fetch version from GitHub, launching existing install."
elif [ "${NETWORK_TAG}" != "${LOCAL_TAG}" -o "$2" == "force" ]; then
	echo Installing latest version of ${downloadPrefix}: ${NETWORK_TAG}

	DL_URL=$(curl -L -s https://api.github.com/repos/${repo}/releases/latest | grep 'browser_' | cut -d\" -f4 | grep -- -${NETWORK_TAG})
	DL_FILE=${DL_URL##*/}
	rm -f "/tmp/${DL_FILE}"
	wget -P /tmp "${DL_URL}"
  if [ $? -ne 0 ]; then
		echo "wget of ${DL_FILE} failed. Aborting update."
		exit 1
	fi

	rm -r ${installDirectory}
	mkdir -p ${installDirectory}
	cd ${installDirectory}
	mv "/tmp/${DL_FILE}" .

	unzip ${DL_FILE}
	chmod 777 *.sh
	#grab dos2unix from the package manager if not installed
	command -v dos2unix >/dev/null 2>&1 || { apt-get install --yes --force-yes dos2unix >&2; }
	grep -lU $'\x0D' *.sh | xargs dos2unix
	#ensure the cwhservice always is linux format and executable
	grep -lU $'\x0D' /etc/init.d/cwhservice | xargs dos2unix
	chmod +x /etc/init.d/cwhservice
	rm ${DL_FILE}
	
	# Now configuring tinkerboard... U3DS customization
	# if does not work, remove
	
	echo "U3DS customizer begins."
	systemctl set-default multi-user.target
        mkdir -p /etc/systemd/system/getty@tty1.service.d/
        cat > /etc/systemd/system/getty@tty1.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root %I $TERM
EOF

else
	echo No install required

fi

echo Turning off screen saver and power saving
xset s off         # don't activate screensaver
xset -dpms         # disable DPMS (Energy Star) features
xset s noblank     # don't blank the video device

if [ ! -f "/etc/init.d/cwhservice" ]; then
	echo Installing CWH as a service
	cp ${installDirectory}/cwhservice /etc/init.d/
	chmod 777 /etc/init.d/cwhservice
	update-rc.d cwhservice defaults
fi

echo Determinging if one time install has occurred
performedOneTimeInstall=$(grep performedOneTimeInstall ${CONFIG_PROPS} | awk -F= '{print $2}')
if [ -f "oneTimeInstall.sh" -a [${performedOneTimeInstall} != "true"] ]; then
	./oneTimeInstall.sh
fi

if [ -f "eachStart.sh" ]; then
	./eachStart.sh
fi

if [ "$2" == "debug" ]; then
	pkill -9 -f "org.area515.resinprinter.server.Main"
	echo "Starting printer host server($2)"
	java -Xmx512m -Xdebug -Xrunjdwp:server=y,transport=dt_socket,address=4000,suspend=n -Dlog4j.configurationFile=debuglog4j2.properties -Djava.library.path=/usr/lib/jni -cp lib/*:. org.area515.resinprinter.server.Main > log.out 2> log.err &
elif [ "$2" == "TestKit" ]; then
	pkill -9 -f "org.area515.resinprinter.test.HardwareCompatibilityTestSuite"
	echo Starting test kit
	java -Xmx512m -Dlog4j.configurationFile=testlog4j2.properties -Djava.library.path=/usr/lib/jni -cp lib/*:. org.junit.runner.JUnitCore org.area515.resinprinter.test.HardwareCompatibilityTestSuite &
else
	pkill -9 -f "org.area515.resinprinter.server.Main"
	echo Starting printer host server
	java -Xmx512m -Dlog4j.configurationFile=log4j2.properties -Djava.library.path=/usr/lib/jni -cp lib/*:. org.area515.resinprinter.server.Main > log.out 2> log.err &
fi

if [ -f "afterStart.sh"]; then
	./afterStart.sh
fi
