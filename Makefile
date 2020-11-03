HOST='root@erebe.eu'
RASPBERRY='pi@192.168.1.253'

.PHONY: install deploy release dns sudo ssh package iptables kubernetes_install k8s dovecot postfix nextcloud nextcloud_resync_file backup app wireguard pihole

deploy: dns sudo ssh package iptables k8s dovecot postfix nextcloud backup wireguard

release:
ifdef ARGS
	kubectl delete pod -n default -l app=$(ARGS) 
	kubectl wait --for=condition=Ready --timeout=-1s -n default -l app=$(ARGS) pod
endif
		
install:
	sops -d --extract '["public_key"]' --output ~/.ssh/erebe_rsa.pub secrets/ssh.yml
	sops -d --extract '["private_key"]' --output ~/.ssh/erebe_rsa.key secrets/ssh.yml
	chmod 600 ~/.ssh/erebe_rsa.*
	grep -q erebe.eu ~/.ssh/config > /dev/null 2>&1 || cat config/ssh_client_config >> ~/.ssh/config
	mkdir ~/.kube || exit 0
	sops -d --output ~/.kube/config secrets/kubernetes-config.yml


dns:
	sops -d --output secrets_decrypted/gandi.yml secrets/gandi.yml
	GANDI_CONFIG='secrets_decrypted/gandi.yml' gandi dns update erebe.eu -f dns/erebe.eu.zones
	GANDI_CONFIG='secrets_decrypted/gandi.yml' gandi dns update erebe.dev -f dns/erebe.dev.zones

ssh:
	ssh ${HOST} "cat /etc/ssh/sshd_config" | diff  - config/sshd_config \
		|| (scp config/sshd_config ${HOST}:/etc/ssh/sshd_config && ssh ${HOST} systemctl restart sshd)

sudo:
	scp config/sudoers ${HOST}:/etc/sudoers.d/erebe

package:
	scp wireguard/wireguard-backport.list ${HOST}:/etc/apt/sources.list.d/
	ssh ${HOST} 'apt-get update && apt-get install -y curl htop mtr tcpdump ncdu vim dnsutils strace linux-perf iftop wireguard'
	# Enable automatic security Updates
	ssh ${HOST} 'echo "unattended-upgrades unattended-upgrades/enable_auto_updates boolean true" | debconf-set-selections && apt-get install unattended-upgrades -y'

iptables:	
	scp config/iptables ${HOST}:/etc/network/if-pre-up.d/iptables-restore
	ssh ${HOST} 'chmod +x /etc/network/if-pre-up.d/iptables-restore && sh /etc/network/if-pre-up.d/iptables-restore'
	
kubernetes_install:
	ssh ${HOST} 'export INSTALL_K3S_EXEC=" --no-deploy servicelb --no-deploy traefik --no-deploy local-storage"; \
		curl -sfL https://get.k3s.io | sh -'

k8s:
	#helm3 repo add stable https://kubernetes-charts.storage.googleapis.com/
	#helm3 repo update
	kubectl apply -f k8s/ingress-nginx-v0.40.2.yml
	kubectl apply --validate=false -f k8s/cert-manager-v1.0.3.yml
	kubectl apply -f k8s/lets-encrypt-issuer.yml

dovecot:
	sops -d --output secrets_decrypted/dovecot.yml secrets/dovecot.yml
	kubectl apply -f secrets_decrypted/dovecot.yml
	kubectl apply -f dovecot/dovecot.yml

postfix:
	sops -d --output secrets_decrypted/fetchmail.yml secrets/fetchmail.yml
	kubectl apply -f secrets_decrypted/fetchmail.yml
	kubectl apply -f postfix/postfix.yml


nextcloud:
	kubectl apply -f nextcloud/config.nginx.site-confs.default.yml
	kubectl apply -f nextcloud/nextcloud.yml

nextcloud_resync_file:
	kubectl exec -t $(shell kubectl get pods -n default -l app=nextcloud -o json | jq .items[].metadata.name) -- sudo -u abc /config/www/nextcloud/occ files:scan --all

backup:
	sops -d --output secrets_decrypted/backup_ftp_credentials.yml secrets/backup_ftp_credentials.yml
	kubectl apply -f secrets_decrypted/backup_ftp_credentials.yml
	kubectl apply -f backup/backup-cron.yml

app:
	kubectl apply -f app/couber.yml
	kubectl apply -f app/crawler.yml

wireguard:
	sops exec-env secrets/wireguard.yml 'cp wireguard/wg0.conf secrets_decrypted/; for i in $$(env | grep _KEY | cut -d = -f1); do sed -i "s#__$${i}__#$${!i}#g" secrets_decrypted/wg0.conf ; done'
	ssh ${HOST} "cat /etc/wireguard/wg0.conf" | diff  - secrets_decrypted/wg0.conf \
		|| (scp secrets_decrypted/wg0.conf ${HOST}:/etc/wireguard/wg0.conf && ssh ${HOST} systemctl restart wg-quick@wg0)
	ssh ${HOST} 'systemctl enable wg-quick@wg0'


pihole:
	sops exec-env secrets/wireguard.yml 'cp pihole/wg0.conf secrets_decrypted/; for i in $$(env | grep _KEY | cut -d = -f1); do sed -i "s#__$${i}__#$${!i}#g" secrets_decrypted/wg0.conf ; done'
	rsync --rsync-path="sudo rsync" secrets_decrypted/wg0.conf ${RASPBERRY}:/etc/wireguard/wg0.conf 
	ssh ${RASPBERRY} 'sudo systemctl enable wg-quick@wg0; sudo systemctl restart wg-quick@wg0'
	kubectl apply -f pihole/pihole.yml
