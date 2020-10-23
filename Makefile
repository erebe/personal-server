HOST='root@erebe.eu'

.PHONY: dns sudo ssh package iptables kubernetes_install k8s dovecot

all: dns sudo ssh package iptables k8s dovecot

dns:
	sops -d --output secrets_decrypted/gandi.yml secrets/gandi.yml
	GANDI_CONFIG='secrets_decrypted/gandi.yml' gandi dns update erebe.eu -f dns/zones.txt

ssh:
	ssh ${HOST} "cat /etc/ssh/sshd_config" | diff  - config/sshd_config \
		|| (scp config/sshd_config ${HOST}:/etc/ssh/sshd_config && ssh ${HOST} systemctl restart sshd)
	sops -d --extract '["public_key"]' --output secrets_decrypted/id_rsa.pub secrets/ssh.yml
	sops -d --extract '["private_key"]' --output secrets_decrypted/id_rsa secrets/ssh.yml

sudo:
	scp config/sudoers ${HOST}:/etc/sudoers.d/erebe

package:
	ssh ${HOST} 'apt-get update && apt-get install -y curl htop mtr tcpdump ncdu vim dnsutils strace linux-perf'
	# Enable automatic security Updates
	ssh ${HOST} 'echo "unattended-upgrades unattended-upgrades/enable_auto_updates boolean true" | debconf-set-selections && apt-get install unattended-upgrades -y'

iptables:	
	scp config/iptables ${HOST}:/etc/network/if-pre-up.d/iptables-restore
	ssh ${HOST} 'chmod +x /etc/network/if-pre-up.d/iptables-restore && sh /etc/network/if-pre-up.d/iptables-restore'
	
kubernetes_install:
	ssh ${HOST} 'export INSTALL_K3S_EXEC=" --no-deploy servicelb --no-deploy traefik --no-deploy=local-storage"; \
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

