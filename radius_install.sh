#!/bin/bash

# ===============================================
# daloRADIUS 2.3 자동 설치 스크립트 (Rocky 8)
# EAP 및 Accounting, 인증서 설정 포함
# ===============================================

# --- 필수 변수 설정 ---
DALORADIUS_ZIP="2.3.zip"
DALORADIUS_URL="https://github.com/lirantal/daloradius/archive/refs/tags/${DALORADIUS_ZIP}"
WEB_ROOT="/var/www/html"
freeradius_path="/etc/raddb"

# --- 1. 필수 패키지 설치 ---
echo "--- 1. 필수 패키지 설치 중..."
sudo dnf -y remove freeradius freeradius-mysql freeradius-utils
sudo rm -rf /etc/raddb
sudo dnf -y install freeradius freeradius-mysql freeradius-utils mariadb-server httpd php php-cli php-fpm php-mysqlnd php-gd php-ldap php-pear php-xml php-mbstring php-curl php-zip php-pdo unzip wget openssl firewalld
sudo pear install DB

# --- 2. daloRADIUS 파일 다운로드 및 압축 해제 ---
echo "--- 2. daloRADIUS 파일 다운로드 및 압축 해제 중..."
if [ ! -f "${DALORADIUS_ZIP}" ]; then
    echo "--- ${DALORADIUS_ZIP} 파일이 존재하지 않아 다운로드합니다."
    sudo wget "${DALORADIUS_URL}"
else
    echo "--- ${DALORADIUS_ZIP} 파일이 이미 존재합니다. 다운로드를 건너뜁니다."
fi

sudo rm -rf "${WEB_ROOT}/daloradius*"
sudo rm -rf "${WEB_ROOT}/radius*"
sudo unzip "${DALORADIUS_ZIP}"
sudo mv "./daloradius-2.3" "${WEB_ROOT}/radius"

# --- 3. MySQL/MariaDB 데이터베이스 설정 ---
echo "--- 3-1. MySQL/MariaDB 데이터베이스 시작 중..."
sudo systemctl start mariadb
sudo systemctl enable mariadb
# --- 3-2. MySQL/MariaDB root 계정 설정 ---
echo "--- 3-2. MySQL/MariaDB root 계정 설정..."
read -sp "MySQL/MariaDB root 비밀번호를 입력하세요: " MYSQL_ROOT_PASSWORD
echo ""
# --- 3-2. daloRadius에서 사용할 DB 설정 ---
echo "--- 3-2. daloRadius에서 사용할 DB 설정..."
read -p "Enter MySQL Host (Enter 입력시 : localhost): " input_host
MYSQL_HOST=${input_host:-"localhost"}
read -p "Enter MySQL Port (Enter 입력시 : 3306): " input_port
MYSQL_PORT=${input_port:-"3306"}
read -p "Enter MySQL Database (Enter 입력시 : radius): " input_db
MYSQL_DATABASE=${input_db:-"radius"}
# --- 3-3. daloRadius에서 사용할 DB에 사용자 설정 ---
echo "--- 3-3. daloRadius에서 사용할 DB에 사용자 설정..."
read -p "Enter MySQL User (Enter 입력시 : radius): " input_user
MYSQL_USER=${input_user:-"radius"}
read -s -p "Enter MySQL Password (Enter 입력시 : radius12#$): " input_pw
MYSQL_PASSWORD=${input_pw:-"radius12#$"}
echo ""


# MySQL root 비밀번호 접속 테스트
# 1차: 변수(${MYSQL_ROOT_PASSWORD})로 비밀번호 접속 테스트
if ! sudo mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1" &> /dev/null; then
    echo "정보: 기존 설정된 변수 비밀번호로 접속 실패. 초기 비밀번호 설정을 시도합니다."
    
    # 비밀번호가 아예 설정되지 않은 초기 상태라고 가정하고 설정 시도
    if ! sudo mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';" &> /dev/null; then
        
        # 1차 실패 시: 기존 비밀번호 직접 입력 요청
        echo "오류: MySQL/MariaDB root 비밀번호 설정에 실패했습니다. 기존에 설정한 root 패스워드가 있다면 입력하세요."
        read -s -p "MySQL/MariaDB root 비밀번호 입력: " MYSQL_ROOT_PASSWORD
        echo ""  # 줄바꿈

        # 2차: 입력받은 비밀번호로 접속 재시도
        if ! sudo mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1" &> /dev/null; then
            echo "오류: MySQL/MariaDB root 비밀번호 설정에 실패했습니다. 기존 패스워드를 확인후 초기 설정 마법사를 재실행하세요. 스크립트를 종료합니다."
            exit 1
        else
            echo "정보: 입력한 기존 root 비밀번호로 접속 성공."
        fi

    else
        echo "MySQL/MariaDB root 비밀번호 설정 완료."
    fi
else
    echo "정보: MySQL root 비밀번호 접속에 성공했습니다. 초기 설정을 건너뜁니다."
fi

# 데이터베이스와 사용자 초기화
echo "MySQL DB(${MYSQL_DATABASE})를 초기화합니다."
sudo mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "DROP DATABASE IF EXISTS \`${MYSQL_DATABASE}\`"

# 사용자 초기화
echo "MySQL의 Radius DB 사용자(${MYSQL_USER})를 초기화합니다."
sudo mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "DROP USER IF EXISTS '${MYSQL_USER}'@'${MYSQL_HOST}';"

# 데이터베이스와 사용자 생성
echo "MySQL DB(${MYSQL_DATABASE})와 사용자(${MYSQL_USER})를 다시 생성합니다."
sudo mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`"
sudo mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'${MYSQL_HOST}' IDENTIFIED BY '${MYSQL_PASSWORD}';"
sudo mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'${MYSQL_HOST}';"
sudo mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "FLUSH PRIVILEGES;"
echo "MySQL/MariaDB database와 사용자 생성 완료."
sudo bash -c "mysql -u root -p\"${MYSQL_ROOT_PASSWORD}\" ${MYSQL_DATABASE} < \"${freeradius_path}/mods-config/sql/main/mysql/schema.sql\""
sudo bash -c "mysql -u root -p\"${MYSQL_ROOT_PASSWORD}\" ${MYSQL_DATABASE} < \"${WEB_ROOT}/radius/contrib/db/mariadb-daloradius.sql\""
echo "MySQL/MariaDB database 적용 완료."

# --- 4. EAP 인증서 설정 ---
echo "--- 4. EAP 인증서 설정 중..."
# 4-1. 유효 기간 설정 (10년 / 3650일)
sudo sed -i -E 's/^(default_days\s*=\s*)(.*)$/\13650/' ${freeradius_path}/certs/server.cnf
sudo sed -i -E 's/^(default_days\s*=\s*)(.*)$/\13650/' ${freeradius_path}/certs/ca.cnf
# 4-2. ca.cnf 항목 변경 ([certificate_authority] 섹션)
sudo sed -i '/^\[certificate_authority\]/,/^\[/ {
    s/^\(countryName\s*=\s*\).*/\1KR/
    s/^\(stateOrProvinceName\s*=\s*\).*/\1Seoul/
    s/^\(localityName\s*=\s*\).*/\1Seoul/
    s/^\(organizationName\s*=\s*\).*/\1freeradius/
    s/^\(emailAddress\s*=\s*\).*/\1admin@example.org/
    s/^\(commonName\s*=\s*\).*/\1"Freeradius Root CA"/
}' ${freeradius_path}/certs/ca.cnf
# 4-3. server.cnf 항목 변경 ([server] 섹션)
sudo sed -i '/^\[server\]/,/^\[/ {
    s/^\(countryName\s*=\s*\).*/\1KR/
    s/^\(stateOrProvinceName\s*=\s*\).*/\1Seoul/
    s/^\(localityName\s*=\s*\).*/\1Seoul/
    s/^\(organizationName\s*=\s*\).*/\1freeradius/
    s/^\(emailAddress\s*=\s*\).*/\1admin@example.org/
    s/^\(commonName\s*=\s*\).*/\1"hsitx-lab.kro.kr"/
}' ${freeradius_path}/certs/server.cnf
# 4-4. server.cnf SAN (Subject Alternative Name) 설정 추가
# v3_req 또는 server 섹션에 subjectAltName 등록 및 alt_names 섹션 추가
if ! sudo grep -q "subjectAltName" ${freeradius_path}/certs/server.cnf; then
    sudo sed -i '/\[ v3_req \]/a subjectAltName = @alt_names' ${freeradius_path}/certs/server.cnf
fi

if ! sudo grep -q "\[alt_names\]" ${freeradius_path}/certs/server.cnf; then
    cat << 'EOF' | sudo tee -a ${freeradius_path}/certs/server.cnf

EOF
fi
sudo sed -i 's/DNS\.1\s*=\s*radius\.example\.com/DNS.1 = hsitx-lab.kro.kr/' "${freeradius_path}/certs/server.cnf"
# clinet.cnf 항목 변경 
sudo sed -i '/^\[client\]/,/^\[/ {
    s/^\(countryName\s*=\s*\).*/\1KR/
    s/^\(stateOrProvinceName\s*=\s*\).*/\1Seoul/
    s/^\(localityName\s*=\s*\).*/\1Seoul/
    s/^\(organizationName\s*=\s*\).*/\1freeradius/
    s/^\(emailAddress\s*=\s*\).*/\1admin@example.org/
    s/^\(commonName\s*=\s*\).*/\1"client"/
}' "${freeradius_path}/certs/client.cnf"

# 4-5. 인증서 재생성 (기존 인증서 삭제 후 bootstrap 실행)
sudo cd ${freeradius_path}/certs
sudo rm -f *.pem *.der *.csr *.crt *.key *.p12 serial* index.txt*
sudo ${freeradius_path}/certs/bootstrap
sudo chmod -R 755 $freeradius_path/certs/
sudo cd ${WEB_ROOT}/radius

# --- 5. FreeRADIUS 설정 (EAP & Accounting 포함) ---
echo "--- 5. FreeRADIUS 설정 중..."
sudo cp -f ${WEB_ROOT}/temp/sql ${freeradius_path}/mods-available/
####sed -i 's|driver = "rlm_sql_null"|driver = "rlm_sql_mysql"|' ${freeradius_path}/mods-available/sql
####sed -i 's|dialect = "sqlite"|dialect = "mysql"|' ${freeradius_path}/mods-available/sql
#####sudo sed -i 's|dialect = ${modules.sql.dialect}|dialect = "mysql"|' ${freeradius_path}/mods-available/sqlcounter
sudo cp "$freeradius_path/mods-available/sqlcounter" "$freeradius_path/mods-available/sqlcounter.bak"
sudo sed -i 's|dialect = ${modules.sql.dialect}|dialect = "mysql"|' "$freeradius_path/mods-available/sqlcounter"
####sudo sed -i 's|#\s*read_clients = yes|read_clients = yes|' ${freeradius_path}/mods-available/sql
#Radius Reply시 attribute 전송하게 함.
sudo cp "$freeradius_path/sites-available/inner-tunnel" "$freeradius_path/sites-available/inner-tunnel.bak"
sudo sed -i 's/if (0) {/if (1) {/' "${freeradius_path}/sites-available/inner-tunnel"

sudo sed -i 's|^server = .*|server = "'$MYSQL_HOST'"|' "${freeradius_path}/mods-available/sql"
sudo sed -i 's|^port = .*|port = "'$MYSQL_PORT'"|' "${freeradius_path}/mods-available/sql"
sudo sed -i 's|^radius_db= .*|radius_db= "'$MYSQL_DATABASE'"|' "${freeradius_path}/mods-available/sql"
sudo sed -i 's|^login = .*|login = "'$MYSQL_USER'"|' "${freeradius_path}/mods-available/sql"
sudo sed -i 's|^password = .*|password = "'$MYSQL_PASSWORD'"|' "${freeradius_path}/mods-available/sql"

####sed -i 's#/etc/ssl#/etc/raddb#g' ${freeradius_path}/mods-available/sql
####sed -i 's#/etc/raddb/certs/private#/etc/raddb/certs#g' ${freeradius_path}/mods-available/sql
sudo cp "$freeradius_path/sites-available/default" "$freeradius_path/sites-available/default.bak"
sudo sed -i 's/-sql/sql/g' "$freeradius_path/sites-available/default"
#####sudo sed -i '/^#\s*update request {/,/^#\s*}/s/^#\s*//' ${freeradius_path}/sites-available/default
sudo rm -f ${freeradius_path}/mods-enabled/sql
sudo rm -f ${freeradius_path}/mods-enabled/sqlcounter
sudo rm -f ${freeradius_path}/mods-enabled/sqlippool
sudo ln -s ${freeradius_path}/mods-available/sql ${freeradius_path}/mods-enabled/sql
sudo ln -s ${freeradius_path}/mods-available/sqlcounter ${freeradius_path}/mods-enabled/sqlcounter
sudo ln -s ${freeradius_path}/mods-available/sqlippool ${freeradius_path}/mods-enabled/sqlippool

# --- 5-1. freeradius에 Ruckus Radius Doctionary 적용 ---
echo "--- 5-1. freeradius에 Ruckus Radius Doctionary 적용중..."
sudo mv dictionary.ruckus ${freeradius_path}
sudo grep -qF '$INCLUDE dictionary.ruckus' "${freeradius_path}/dictionary" || sudo sed -i '$a\$INCLUDE dictionary.ruckus' "${freeradius_path}/dictionary"
# --- 5-2. MySQL/MariaDB에 Ruckus Radius Doctionary import ---
echo "--- 5-2. MySQL/MariaDB에 Ruckus Radius Doctionary import중..."
# 기존 DB에 동일한 Ruckus Vendor attributes가 있다면 중복 방지를 위해 삭제 후 재등록
sudo mysql -u root -p"${MYSQL_ROOT_PASSWORD}" "${MYSQL_DATABASE}" -e "DELETE FROM dictionary WHERE Vendor = 'Ruckus';"
# dictionary.ruckus 파일에서 ATTRIBUTE 라인만 추출하여 DB에 INSERT
awk '
BEGIN {
    vendor = "Ruckus"
}
/^ATTRIBUTE/ {
    # 연속된 공백/탭을 하나로 처리
    attr_name = $2
    attr_type = $4
    
    if (attr_name != "" && attr_type != "") {
        printf "INSERT INTO dictionary (Type, Attribute, Vendor) VALUES (\x27%s\x27, \x27%s\x27, \x27%s\x27);\n", attr_type, attr_name, vendor
    }
}
' "${freeradius_path}/dictionary.ruckus" | sudo mysql -u root -p"${MYSQL_ROOT_PASSWORD}" "${MYSQL_DATABASE}"

# --- 6. daloRADIUS 설정 ---
echo "--- 6. daloRADIUS 설정 중..."
sudo cp "${WEB_ROOT}/radius/library/daloradius.conf.php.sample" "${WEB_ROOT}/radius/library/daloradius.conf.php"
####sed -i "s/\$configValues\['CONFIG_DB_ENGINE'\] = '.*';/\$configValues\['CONFIG_DB_ENGINE'\] = 'mysqli';/" "${WEB_ROOT}/radius/library/daloradius.conf.php"
sudo sed -i "s/\$configValues\['CONFIG_DB_HOST'\] = '.*';/\$configValues\['CONFIG_DB_HOST'\] = '${MYSQL_HOST}';/" "${WEB_ROOT}/radius/library/daloradius.conf.php"
sudo sed -i "s/\$configValues\['CONFIG_DB_USER'\] = '.*';/\$configValues\['CONFIG_DB_USER'\] = '${MYSQL_USER}';/" "${WEB_ROOT}/radius/library/daloradius.conf.php"
sudo sed -i "s/\$configValues\['CONFIG_DB_PASS'\] = '.*';/\$configValues\['CONFIG_DB_PASS'\] = '${MYSQL_PASSWORD}';/" "${WEB_ROOT}/radius/library/daloradius.conf.php"
sudo sed -i "s/\$configValues\['CONFIG_DB_NAME'\] = '.*';/\$configValues\['CONFIG_DB_NAME'\] = '${MYSQL_DATABASE}';/" "${WEB_ROOT}/radius/library/daloradius.conf.php"
sudo chown -R apache:apache "${WEB_ROOT}/radius"
sudo chmod -R 775 "${WEB_ROOT}/radius"

# --- 7. daloRADIUS에 NAS 추가후 radius 재시작 버튼 추가하기 위한 파일 수정 ---
# --- 7.1 menu-mng-rad-nas.php, mng-rad-nas.php 수정 ---
#echo "--- 7.1 menu-mng-rad-nas.php, mng-rad-nas.php 수정중..."
#sudo cp -f ${WEB_ROOT}/temp/menu-mng-rad-nas.php ${WEB_ROOT}/radius
#sudo cp -f ${WEB_ROOT}/temp/mng-rad-nas.php ${WEB_ROOT}/radius

# --- 7.2 mng-rad-attributes-del.php 수정 ---
#echo "--- 7.2 mng-rad-attributes-del.php 수정중..."
#sudo cp -f ${WEB_ROOT}/temp/mng-rad-attributes-del.php ${WEB_ROOT}/radius

# --- 7-3. daloRADIUS에 Accounting Table 수정 ---
#echo "--- 7-3. daloRADIUS에 Accounting Table(rep-online.php) 수정중..."
#sudo cp -f ${WEB_ROOT}/temp/rep-online.php ${WEB_ROOT}/radius

# --- 7-4. daloRADIUS에서 로그 보기위해 수정 ---
sudo touch /var/log/daloradius.log
sudo chmod 777 /var/log/daloradius.log
#sudo sed -i "s/\$configValues\['CONFIG_LOG_FILE'\] = '.*';/\$configValues\['CONFIG_LOG_FILE'\] = '\/var\/log\/daloradius.log';/" "${WEB_ROOT}/radius/library/daloradius.conf.php"

# --- 8. 서비스 시작 및 방화벽 설정 ---
# --- 8-1. 웹, Radius 서비스 시작 ---
sudo cp -f ./daloradius-users.conf /etc/httpd/conf.d/daloradius-users.conf
sudo cp -f ./daloradius-operators.conf /etc/httpd/conf.d/daloradius-operators.conf
echo "--- 8-1. 웹, Radius 서비스 시작 중..."
sudo systemctl start httpd
sudo systemctl enable httpd
sudo systemctl restart radiusd
sudo systemctl enable radiusd
sudo systemctl enable php-fpm
sudo systemctl restart php-fpm
# --- 8-2. Radius log파일 권한 설정 ---
echo "--- 8-2. Radius log파일 권한 설정 중..."
sudo chmod -R 755 /var/log/radius/
sudo chmod -R 744 /var/log/radius/radius.log
sudo chmod 644 /var/log/messages
# --- 8-3. 방화벽 서비스 시작 ---
echo "--- 8-3. 방화벽 서비스 시작 중..."
sudo systemctl enable firewalld
sudo systemctl restart firewalld
sudo firewall-cmd --add-service=http --permanent
sudo firewall-cmd --add-service=https --permanent
sudo firewall-cmd --add-port=1812/udp --permanent
sudo firewall-cmd --add-port=1813/udp --permanent
sudo firewall-cmd --add-port=8000/tcp --permanent
sudo firewall-cmd --add-port=8080/tcp --permanent
sudo firewall-cmd --reload
#SElinux 허용
sudo setenforce 0
# --- SELINUX=enforcing 일 경우에만 SELINUX=permissive로 변경 ---
sudo sed -i '/^SELINUX=enforcing/s/enforcing/permissive/' /etc/selinux/config

# --- 9. 설치에 필요한 임시 파일들을 삭제 ---
echo "--- 9. 설치에 필요한 임시 파일들을 삭제중..."
sudo cd ${WEB_ROOT}/temp
sudo mv ./README ../radius
sudo cd ../
sudo rm -rf ${WEB_ROOT}/temp


echo "==============================================="
echo "✅ daloRADIUS 설치가 완료되었습니다!"
echo "웹 브라우저에서 아래 주소로 접속하세요:"
echo "    http://<서버_IP_주소>/private/radius"
echo ""
echo "기본 로그인 정보:"
echo "    - 사용자명: administrator"
echo "    - 비밀번호: radius"
echo "✅ 초기 관리자 비밀번호는 Config > Operators > List Operators 메뉴를 통해 변경하세요!"
echo "✅ Ruckus Radius Dictionary는 Management > Attributes > Import Vendor Dictionary를 통해 import하세요!"
echo "==============================================="
