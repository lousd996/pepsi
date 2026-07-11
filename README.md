# 下载到本地执行
wget -O install_xui.sh https://raw.githubusercontent.com/lousd996/pepsi/main/install_xui.sh

chmod +x install_xui.sh

sudo bash install_xui.sh


cd /etc/x-ui

rm -f x-ui

wget -O x-ui.db https://raw.githubusercontent.com/lousd996/pepsi/main/x-ui.db


reboot
