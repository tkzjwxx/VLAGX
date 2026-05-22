kill -9 $(pgrep apt) 2>/dev/null; rm -f /var/lib/dpkg/lock* ; dpkg --configure -a ; rm -f /etc/resolv.conf && echo -e "nameserver 2a09:bac5:d46f:e6::1\nnameserver 2001:67c:2b0::4\nnameserver 2001:67c:2b0::6" > /etc/resolv.conf && apt update -y && apt install -y curl wget screen && wget -O install.sh https://ghproxy.net/https://raw.githubusercontent.com/tkzjwxx/VLAGX/refs/heads/main/install.sh && chmod +x install.sh && ./install.sh





kill -9 $(pgrep apt) 2>/dev/null; rm -f /var/lib/dpkg/lock* ; dpkg --configure -a ; rm -f /etc/resolv.conf && echo -e "nameserver 2a09:bac5:d46f:e6::1\nnameserver 2606:4700:4700::1111\nnameserver 2001:67c:2b0::4" > /etc/resolv.conf && apt update -y && apt install -y curl wget screen && wget -O install.sh https://raw.githubusercontent.com/tkzjwxx/VLAGX/refs/heads/main/install.sh && chmod +x install.sh && ./install.sh
