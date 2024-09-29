# Managing my personal server in ~~2020~~ 2023

<p align="center">
  <img src="https://github.com/erebe/personal-server/raw/master/logo.jpeg" alt="logo"/>
</p>

### Updates:
 * 29 July 2023 - Replaced iptables config by nftables
 * 31 october 2022 - feedback from 2 years old insights [2023 update](#2023)
 * 9 september 2021 - Added dns over https for pihole
 * 22 December 2020 - Added [https://healthchecks.io](https://healthchecks.io) for backups to ping me on whatsapp
 * 20 November 2020 - Mention of gpg key to sign git commits
 * 12 November 2020 - Add automatic deployment


# Summary

This document is going to describe how I manage my personal server in 2020. It will talk about

* Management of secrets with SOPS and a GPG key
* Automatic management of DNS record
* Configuration of Debian and installation of Kubernetes k3s
* Setup Nginx ingress with let's encrypt for automatic TLS certificate
* Deployment of postfix + dovecot for deploying an email server
* Install Nextcloud to get your personal cloud in the sky
* Putting backup in place
* Using Wireguard to create a private network and WsTunnel to bypass firewalls
* Adding a Raspberry Pi to the K3s cluster

My goals for this setup are:

* Simple to deploy, manage and update
* Everything should live inside the git repository
* Automating as much as possible with free tier service (GitHub actions) but reproducible locally
* Package and deploy the same way system application and my own projects

# Table of Contents

1. [The road so far](#background)

**PART I**: The Setup

2. [Creating GPG key](#gpg)
3. [Encrypting secrets with Sops](#sops)
4. [Generating a new ssh key](#ssh)
5. [Automating installation with a Makefile](#makefile)
6. [Chose a server provider](#provider)
7. [Secure and Automate installation of the base machine](#secure)
8. [Chose your registrar for DNS](#dns)
9. [Automate your DNS record update](#dnsupdate)
10. [Installing Kubernetes K3S](#k3s)
11. [Nginx as Ingress controller for Kubernetes](#ingress)
12. [CertManager with let's encrypt for issuing TLS certificates](#letsencrypt)

**PART II**: Build, Deploy and Automate

13. [Mail Server with Postfix + Dovecot + Fetchmail + SpamAssassin](#mail)
14. [Automating build and push of our images with GitHub actions](#build)
15. [Automatic deployment with Webhook](#deployment)
16. [Hosting your own cloud with nextcloud](#cloud)

**PART III**: Reliability and Observability

17. [Backups](#backup)
18. [TODO] [Monitoring with netdata](#monitoring)

**PART IV**: Scale with RaspberryPI

19. [VPN with Wireguard](#wireguard)
20. [Bypass firewalls with WsTunnel](#wstunnel)
21. [Raspberry Pi as k8S node using your Wireguard VPN](#raspberry)
22. [Deploying PiHole on your Raspberry Pi](#pihole)

**PART V**: The end

23. [Conclusion](#conclusion)
24. [If you want more freedom](#freedom)

**EPILOGUE**: [2023 - feedbacks from 2 years insights](#2023)

25. [Security](#2023_security)
26. [Maintainability](#2023_maintainability)
27. [Extensibility](#2023_extensibility)
28. [Observability](#2023_observability)
28. [2023 Conclusion](#2023_conclusion)

# The road so far <a name="background"></a>


<p></p>

It has been more than 15 years now that I manage my own dedicated server, I am in my thirties, and it all started thanks to a talk from Benjamin Bayart [Internet libre, ou minitel 2.0](https://www.youtube.com/watch?v=AoRGoQ76PK8) or for the non-French "Free internet or minitel 2.0". For those who don't know what is a minitel, let me quote for you Wikipedia.

> The Minitel was a videotex online service accessible through telephone lines, and was the world's most successful online service prior to the World Wide Web. It was invented in Cesson-Sévigné, near Rennes in Brittany, France.

In the essence, the talk is about creating awareness in 2007 that the internet is starting to lose its decentralized nature and look like more to a minitel 2.0 due to our reliance on centralized big corp for about everything on the Web. This warning ring even louder nowadays with the advent of the Cloud where our computers are now just a fancy screen for accessing data/compute remotely.

I went from hardcore extremist, by hosting a server made from scrap materials behind my parent house telephone line, using Gentoo to recompile everything, control every USE flags and have the satisfying pleasure of adding `-mtune=native` to the compilation command line. Some years later, after being fed up with having to spend nights to recompile everything on an old Intel Pentium 3 because I missed a USE flag that was mandatory to try this new software, I switched to Debian.

At that point I thought I had the perfect setup, just do an `apt-get install` and you have your software installed in a few minutes, is there anything more than that really ?

It was at that time also that I switched from hosting my server at my parent house to a hosting company. I was out for college and calling my parents to ask them to reboot the machine because it froze due to aging components was taking too much time. I was living in the constant fear of losing some emails and friends on IRC were complaining that the archive/history of the channel that my server was providing was not accessible anymore. So as hard as the decision had been, especially since everything was installed by hand without configuration management, I went to see my parents to tell them that I am removing the server from their care to host it on `online.net` and that they should expect even fewer calls from me from now on.

Rich of this new available bandwidth and after porting my manual deployments to Ansible, I really thought this time I had the perfect setup. Easy to install and configured management ! Is there anything more than that really ?

I had found my cruise boat and sailed peacefully with it until the dependencies monsters knocked me off board. When you try to **CRAM** everything (mail, webserver, gitlab, pop3, imap, torrent, owncloud, munin, ...) into a single machine on Debian, you ultimately end-up activating unstable repository to get the latest version of packages and end-up with conflicting versions between softwares to the point that doing an `apt-get update && apt-get upgrade` is now your nemesis.

While avoiding system upgrade, I spent some time playing with Kvm/Xen, FreeBSD jails, Illumos, micro-kernel (I thought it will be the future :x) and the new player in town Docker ! I ended-up using Docker due to being too busy/lazy to reinstall everything on something new and Docker allowed me to progressively isolate/patch the software that were annoying me. Hello Python projects !

This hybrid setup worked for a while, but it felt clunky to manage, especially with Ansible in the mix. I ended-up moving everything into containers, not without hassle :kiss: postfix, and now Ansible was feeling at odd and the integration between systemd and Docker weird, I was just spending time gluing trivial things.

So I spent a bit of time this month to create and share with you my perfect new setup for managing a personal server in 2020 !

# Creating a GPG key <a name="gpg"></a>

So let's start. The first step is to create a GPG key. This key will serve to encrypt every secret we have in order to be able to commit them inside the git repository. With secrets inside git, our repository will be able be standalone and portable across machines. We will be able to do a `git clone` and get working !

```bash
gpg --full-generate-key
```

This GPG key will be the guardian of your infrastructure, if it leaks, anybody will be able to access your infra. So store it somewhere safe [i.e on a YubiKey](https://www.yubico.com/)

```bash
gpg --armor --export erebe@erebe.eu > pub.asc
gpg --armor --export-secret-key erebe@erebe.eu > private.asc
```

If you haven't already done it, you can even sign your git commit in order to have the "verfied" label in github thanks to your pgp key.
[How to to it is explained here](https://docs.github.com/en/free-pro-team@latest/github/authenticating-to-github/about-commit-signature-verification)

# Encrypting secrets with sops <a name="sops"></a>

Now that we have a PGP key, we will use the wonderful tool [SOPS](https://github.com/mozilla/sops) to encrypt our secrets with it.

Sops is not very well known, but very practical and easy to use, which is a great plus for once in a security tool.

To use it, create a config file at the root of your repository

```bash
❯ cat .sops.yaml
creation_rules:
    - pgp: >-
        YOUR_PGP_FINGERPRINT_WITHOUT_SPACE
```

After that just invoke sops to create a new secret with your GPG key. Sops force the use of YAML, so your file need to be a valid YAML.

```bash
❯ mkdir secrets secrets_decrypted
❯ sops secrets/foobar.yml
* editor with default values *
❯ cat secrets/foorbar.yml # content of file is encrypted now
hello: ENC[AES256_GCM,data:zpzQz+siZxcshJjmi4PBvX2GMm3sWibxRPCgil2mi+c6AQ0uXEBLM2lL0o+BBg==,
...
```

To decrypt your secrets just do a

```bash
sops -d --output secrets_decrypted/foobar.yml secrets/foorbar.yml
```
----------
**Info** If you have an issue like this one below when trying to decrypt
```
    - | could not decrypt data key with PGP key:
      | golang.org/x/crypto/openpgp error: Could not load secring:
      | open /home/chronos/user/.gnupg/secring.gpg: no such file or
      | directory; GPG binary error: exit status 2
```

Try doing in your terminal
```
GPG_TTY=$(tty)
export GPG_TTY
```
https://github.com/mozilla/sops/issues/304#issuecomment-377195341

---------


There are other commands that allow you to avoid dumping your decrypted secrets onto the file system. If you are interested in this feature look at

```bash
sops exec-env
# or
sops exec-file
```

# Generating a new ssh key <a name="ssh"></a>

Now that we are able to store secrets securely within our repository, it is time to generate a new ssh key in order to be able to log to our future next server.

We are going to set a passphrase to our ssh keys and use a ssh-agent/[keychain](https://www.funtoo.org/Keychain) in order to avoid typing it every time

```bash
# Don't forget to set a strong passphrase and change the default name for your key from id_rsa to something else, it will be useful later on
ssh-keygen

# To add your ssh key into the keyring
eval $(keychain --eval --agents ssh ~/.ssh/your_private_key)
```

We are going to commit this ssh key into the repository with sops

```bash
sops secrets/ssh.yml
# edit the yaml file to get 2 section for your private and public ssh key
# paste the content of your keys in this section

git add secrets/ssh.yml
git commit -m 'Adding ssh key'
```

# Automating installation with a Makefile <a name="makefile"></a>

Now we want for this repository to be self-contained and easily portable across machines. A valid approach would have been to use Ansible in order to automate our deployment. But we will not tap a lot into the full power of a configuration management in this setup, so I chose to use a simple makefile to automate the deployment.

```bash
❯ mkdir config
❯ cat Makefile
.PHONY: install

install:
        sops -d --extract '["public_key"]' --output ~/.ssh/erebe_rsa.pub secrets/ssh.yml
        sops -d --extract '["private_key"]' --output ~/.ssh/erebe_rsa.key secrets/ssh.yml
        chmod 600 ~/.ssh/erebe_rsa.*
        grep -q erebe.eu ~/.ssh/config > /dev/null 2>&1 || cat config/ssh_client_config >> ~/.ssh/config
        mkdir ~/.kube || exit 0

```

The installation section is decrypting the ssh keys, install them and looking into my \~/.ssh/config to see if I already have a section for my server in order to add it if missing. With that I will be able to do a `ssh my-server` and get everything setup correctly

# Chose a server provider <a name="provider"></a>

We have a git repository with our ssh keys, so now is the time to use those keys and get a real server behind it.

Personally I use a 1st tier [dedibox](https://www.scaleway.com/fr/dedibox/tarifs/) from `online.net` now renamed into `scaleway` for 8€ per month. Their machine is rock solid, cheap and never had an issue with them since more than 15 years. You are free to chose whatever provider you want but here my recommendations for the thing to look at

* **Disk space**: Using containers consume a lot of disk space. So take a machine with at least 60G of space.
* **Public bandwidth limitation**: All hosting company throttle public bandwidth to avoid issue with torrent seedbox. So the higher you get for the same price, the better it is (i.e: scaleway provide 250Mbits/s while OVH only 200Mbits)
* **Free backup storage**: At some point we will have data to backup, so look if they provide some external storage for backups
* **IPv6**: They should provide IPv6. Not mandatory, but it is 2020
* **Domain name/Free mail account**: If you plan to use them as a registrar for your domain name, look if they can provide you email account storage in order to configure them as fallback to not lose mail

Once you have your server provider, do the installation and choose Debian for the OS. At some point they will ask you for your ssh key, so provide the one you created earlier.
If you have the possibility to select your filesystem use XFS instead of ext4 as it provides good support for container runtime.

If everything is installed correctly you should be able to do a

```bash
ssh root@ip.of.the.server
```

# Secure and automate installation of base machine <a name="secure"></a>

The machine is in place and reachable to the outside world.
First thing to do is secure it ! We want to :

* Allow automatic security update
* Tighten SSH server access
* Restrict network access

### Enable automatic security update
Let's start by enabling the automatic security update of Debian.
In our Makefile

```bash
HOST=${my-server}

.PHONY: install package
# ...
package:
        ssh ${HOST} 'apt-get update && apt-get install -y curl htop mtr tcpdump ncdu vim dnsutils strace
linux-perf iftop'
        # Enable automatic security Updates
        ssh ${HOST} 'echo "unattended-upgrades unattended-upgrades/enable_auto_updates boolean true" | de
bconf-set-selections && apt-get install unattended-upgrades -y'

```
With that the machine is installing security update by its own, without requesting us to type manually `apt-get update && apt-get upgrade`

### Secure SSH server
Next is improving the security of our ssh server.

We are going to disable password authentication and allowing only public key authentication.
As our ssh keys are encrypted in our repository, they will be always available to us if needed (as long as we have the GPG key).

The main config options for your sshd_config
```bash
PermitRootLogin prohibit-password
PubkeyAuthentication yes
AllowUsers erebe root
X11Forwarding no
StrictModes yes
IgnoreRhosts yes
```

As I don't use any configuration management (i.e: Ansible), It is kind of tedious to use a normal user and leverage privilege escalation (sudo) to do stuff in `root`. So I allow root login on the SSH server to make things easier to manage. If you plan to use a configuration management system, disable the root login authentication.

Now let's use again our Makefile to automate the deployment of the config

**Warning** Be sure that you are correctly able to log with your ssh key before doing that or you will need to reinstall your machine/use the rescue console of your hosting provider to fix things

```bash
❯ Makefile
.PHONY: install package ssh

#...

# Check if the file is different from our git repository and if it is the case re-upload and restart the ssh server
ssh:
        ssh ${HOST} "cat /etc/ssh/sshd_config" | diff  - config/sshd_config \
                || (scp config/sshd_config ${HOST}:/etc/ssh/sshd_config && ssh ${HOST} systemctl restart
```

if you want to go a step further, you can

* Change default ssh server port
* Disallow root authentication
* [Enable 2-factor authentication with google-authentificator](https://www.globo.tech/learning-center/setup-ssh-server-with-two-factor-authentication-ubuntu-debian/) (it does not contact google)


### Secure Network access

**Deprecated** Now using nftables, but iptables still works, so you can keep reading

Last part of the plan is to secure the network by putting in place firewall rules.

I want to stay close to the real things, so I use directly iptables to create my firewall rules. This is at the cost of having to duplicate the rules for IPv4 and IPv6.

**If you want to simplify you the task please use [UFW - Uncomplicated Firewall](https://www.digitalocean.com/community/tutorials/how-to-set-up-a-firewall-with-ufw-on-debian-9)**

We want for our deployment of iptables rules to be idempotent, so we are going to create a custom chain to avoid messing with the default one.
Also, I am going to use `iptables` command directly instead of `iptable-restore`, because `iptables-restore` files need to be holistic and does not compose well when programs manage only a subpart of the firewall rules. As we are going to install Kubernetes later on, it will allow us to avoid messing with proxy rules.

```bash
#!/bin/sh

# Execute only when it is for our main NIC
[ "$IFACE" != "enp1s0" ] || exit 0

# In order to get an IPv6 lease/route from online.net
sysctl -w net.ipv6.conf.enp1s0.accept_ra=2

###########################
# IPv4
###########################
# Reset our custom chain
iptables -P INPUT ACCEPT
iptables -D INPUT -j USER_CUSTOM
iptables -F USER_CUSTOM
iptables -X USER_CUSTOM

iptables -N USER_CUSTOM

# Allow loopback interface
iptables -A USER_CUSTOM -i lo -j ACCEPT

# Allow wireguard interface
iptables -A USER_CUSTOM -i wg0 -j ACCEPT

# Allow Kubernetes interfaces
iptables -A USER_CUSTOM -i cni0 -j ACCEPT
iptables -A USER_CUSTOM -i flannel.1 -j ACCEPT

# Allow already accepted connections
iptables -A USER_CUSTOM -p tcp  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A USER_CUSTOM -p udp  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A USER_CUSTOM -p icmp -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Accept incoming ICMP - Server provider use ping to monitor the machine
iptables -A USER_CUSTOM -p icmp -j ACCEPT

# Allow ssh
iptables -A USER_CUSTOM -p tcp --dport 22 -j ACCEPT

# Allow http/https
iptables -A USER_CUSTOM -p tcp --dport 80 -j ACCEPT
iptables -A USER_CUSTOM -p tcp --dport 443 -j ACCEPT

# Allow SMTP and IMAP
iptables -A USER_CUSTOM -p tcp --dport 25 -j ACCEPT
iptables -A USER_CUSTOM -p tcp --dport 993 -j ACCEPT

# Allow wireguard
iptables -A USER_CUSTOM -p udp --dport 995 -j ACCEPT

# Allow kubernetes k3S api server
# We are going to disable it after setting up our VPN to not expose it to internet
iptables -A USER_CUSTOM -p tcp --dport 6443 -j ACCEPT


# Add our custom chain
iptables -I INPUT 1 -j USER_CUSTOM

# DROP INCOMING TRAFFIC by default if nothing match
iptables -P INPUT DROP

#######
#IPv6
#######
#do the same thing with ip6tables instead of iptables

# Accept incoming ICMP
ip6tables -A USER_CUSTOM -p icmpv6 -j ACCEPT

# Allow ipv6 route auto configuration if your provider support it
ip6tables -A USER_CUSTOM -p udp --dport 546 -j ACCEPT
ip6tables -A USER_CUSTOM -p icmpv6 --icmpv6-type router-advertisement -j ACCEPT
ip6tables -A USER_CUSTOM -p icmpv6 --icmpv6-type router-solicitation -j ACCEPT
ip6tables -A USER_CUSTOM -p icmpv6 --icmpv6-type neighbour-advertisement -j ACCEPT
ip6tables -A USER_CUSTOM -p icmpv6 --icmpv6-type neighbour-solicitation -j ACCEPT
ip6tables -A USER_CUSTOM -p icmpv6 --icmpv6-type echo-request -j ACCEPT
ip6tables -A USER_CUSTOM -p icmpv6 --icmpv6-type echo-reply -j ACCEPT
```

I don't rate limit ssh connections, as most of the time it is me that is hit by that limit. Nowadays most bot scanning ssh servers are smart enough to time their attempts to avoid being rate limited.
Even if we are only allowing public key authentication, some bots are going to try endlessly to connect to our SSH server, in hope that someday a breach appears. Like waves crashing tirelessly on the shore.

If you want to enable it anyway, you need to add those rules

```bash

-A USER_CUSTOM -p tcp -m conntrack --ctstate NEW --dport 22 -m recent --set --name SSH
-A USER_CUSTOM -p tcp -m conntrack --ctstate NEW --dport 22 -m recent --update --seconds 60 --hitcount 4 --rttl --name SSH -j DROP
-A USER_CUSTOM -p tcp -m conntrack --ctstate NEW --dport 22 -j ACCEPT
```

We are going to deploy those rules in the `if-pre-up` to restore them automatically when the machine reboots. As those rules are idempotent we force their execution when invoked to be sure they are in place.

```bash
iptables:
        scp config/iptables ${HOST}:/etc/network/if-pre-up.d/iptables-restore
        ssh ${HOST} 'chmod +x /etc/network/if-pre-up.d/iptables-restore && sh /etc/network/if-pre-up.d/iptables-restore'
```



# Chose your registrar (DNS) <a name="dns"></a>

Now that we have a server provisioned and a bit more secure, we want to assign it a cute DNS name instead of just its IP address.
If you don't know what is a DNS please refer to :
* [Wikipedia](https://en.wikipedia.org/wiki/Domain_Name_System)
* [Cloudflare blog post](https://www.cloudflare.com/learning/dns/what-is-dns/)

Like for the server provider, you are free to chose whatever you want here.

I personally use [GANDI.net](https://www.gandi.net), as they provide free mailbox with a domain name. While I run a postfix/mail server on my server to receive and store emails, to avoid having to set up and manage a tedious DKIM I use GANDI SMTP mail server to send my emails and be trusted/not end up as spams. More on that later in setup your mail server.



If you don't know which one to take, here the point I look for:

* Provide an API to manage DNS record
* Propagation should be fast enough (if you plan to use let's encrypt DNS challenge for wildcard)
* Provide DNSSEC (I don't use it personally)

Beside that every registrar are the same. I recommend you using
* Your hosting company for your registrar in order to centralize things
* Use [Cloudflare](https://www.cloudflare.com) if you plan to setup a blog later on

# Automate your DNS record update <a name="dnsupdate"></a>

This one is simple, just need to get the information of how to use the API of your registrar.
For gandi, we will use their cli `gandi` and manage our zone in a plain text file.

In our Makefile, it gives something like
```bash
dns:
        sops -d --output secrets_decrypted/gandi.yml secrets/gandi.yml
        GANDI_CONFIG='secrets_decrypted/gandi.yml' gandi dns update erebe.eu -f dns/zones.txt
```

with our `zones.txt` file looking

```
@ 10800 IN SOA ns1.gandi.net. hostmaster.gandi.net. 1579092697 10800 3600 604800 10800
@ 10800 IN A 195.154.119.61
@ 10800 IN AAAA 2001:bc8:3d8f::cafe
@ 10800 IN MX 1 mail.erebe.eu.
@ 10800 IN MX 10 spool.mail.gandi.net.
@ 10800 IN MX 50 fb.mail.gandi.net.
api 10800 IN A 195.154.119.61
api 10800 IN AAAA 2001:bc8:3d8f::cafe
...
```

Depending from your registrar, FAI and the TTL you set on your records, it can take quite some time for the new record to be propagated/updated everywhere, so be patient !


# Installing Kubernetes k3s <a name="k3s"></a>

We now have a server secured, with a domain name attached, and that we can re-install at ease.

The next step is to install Kubernetes on it. The choice of Kubernetes can be a bit controversial for only using it on a single machine. Kubernetes is a container orchestrator, so you can only leverage its full power when managing a fleet of servers.
In addition, running vanilla Kubernetes require installing ETCD and other heavyweight components, plus some difficulties configuring every module for them to work correctly together.

Luckily for us an alternative to this heavy/production vanilla installation exists.

Meet [K3S](https://k3s.io/), a trimmed and packaged Kubernetes cluster in a single binary. This prodigy is bought to us by rancher labs, one of the big player in the container operator world. They took the decision for you (replacing ETCD by SQLite, network overlay, load balancer, ...) in order for k3s to be the smallest possible and easy to setup. Yet it is a 100% compliant Kubernetes cluster.

The main benefit of having Kubernetes installed on my server, is that it allow me to have a standard interface for all my deployments, have everything store in git and allows me to leverage other tools like [skaffold](https://skaffold.dev/) when I am developing my projects. My server is also my playground, so it is great to stay in touch with the fancy stuff of the moment.

**Warning** With everything installed, just having the Kubernetes server components running add a {5%, 10%} CPU on my `Intel(R) Atom(TM) CPU  C2338  @ 1.74GHz 2cores`. So if you are already CPU bound, don't use it or scale up your server.

Let's start, to install K3s nothing more complicated than
```bash
kubernetes_install:
        ssh ${HOST} 'export INSTALL_K3S_EXEC=" --disable servicelb --disable traefik --disable local-storage"; \
                curl -sfL https://get.k3s.io | sh -'
```

We are disabling some more components as we don't need them. Specifically:

* `servicelb` Everything will live on the same machine, so there is no need to load balance, most of the time we are going to avoid the network overlay also, by using the host network directly as much as possible

* `traefik` I have more experience with Nginx/HAProxy for reverse-proxy, so I am going to use nginx ingress controller in place of Traefik. Feel free to use it if you want

* `local-storage` this application is for creating automatically local volume (PV) for your hosts, as we have only one machine, we will bypass this complexity and just use `HostPath` volume

After running this command, you can ssh on your server and do a
```bash
sudo kubectl get nodes
# logs are available with
# sudo journalctl -feu k3s
```
and check that your server is in Ready state (it can take some time). If it is the case, congrats ! You have a Kubernetes control plane working !

Now that this is done, we need to automate the setup of the kubeconfig installation.

On your server copy the content of the kube config file `/etc/rancher/k3s/k3s.yaml` and encrypt it with sops under `secrets/kubernetes-config.yml`. **Be sure to Replace** 127.0.0.1 in the config by the ip/domain name of your server.

After that, in your Makefile add in the install section

```bash
install:
        ...
        mkdir ~/.kube || exit 0
        sops -d --output ~/.kube/config secrets/kubernetes-config.yml
```

If you made things correctly and that you have kubectl installed on your local machine, you should be able to do a
```
kubectl get nodes
```
and see your server ready !


# Nginx as Ingress controller for Kubernetes  <a name="ingress"></a>

I have many small pet projects exposing an HTTP endpoint that I want to expose to the rest of the internet. As I have blocked every ingoing traffic other than for port 80 and 443, I need to multiplex every application under those two. For that I need to install a reverse proxy that will also do TLS termination.

As I have disabled Traefik, the default reverse-proxy, during the k3s installation, I need to install my own. My choice went to Nginx. I know it well with HaProxy, knows it is reliable and it is the most mature between the two on Kubernetes.


To install it on your K3s cluster either use the Helm chart or directly with a kube apply. Refer for the installation guide for [baremetal](https://kubernetes.github.io/ingress-nginx/deploy/#bare-metal)

**WARNING**: Don't copy-paste directly from the documentation nginx-ingress annotations, the '-' is not a real '-' and your annotation will not be recognized :facepalm:

To avoid having to manage also helm deployment, I am going to install it directly from the YAML files available at
```
https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v0.40.2/deploy/static/provider/baremetal/deploy.yaml
```


I am just editing the deployment in order for the Nginx reverse proxy to use `HostNetwork` and avoid going thought the network overlay.
In the above YAML file, replace DNS policy value by `ClusterFirstWithHostNet` and add a new entry `hostNetwork: true` for the container to use directly your network card instead of a virtual interface.


```yaml
# Source: ingress-nginx/templates/controller-deployment.yaml
apiVersion: apps/v1
kind: Deployment
...
    spec:
      dnsPolicy: ClusterFirstWithHostNet
      hostNetwork: true
      containers:
...
```
If you are using the helm chart, there is a variable/flag to toggle the usage of host network.
Save your YAML file in your repository and update your Makefile to deploy it

```Bash
k8s:
        # If you use helm
        #helm3 repo add stable https://kubernetes-charts.storage.googleapis.com/
        #helm3 repo update
        # helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
        # helm install ingress-nginx ingress-nginx/ingress-nginx --set controller.hostNetwork=true

        kubectl apply -f k8s/ingress-nginx-v0.40.2.yml
        kubectl wait --namespace ingress-nginx \
            --for=condition=ready pod \
            --selector=app.kubernetes.io/component=controller \
            --timeout=120s
```

For more information regarding Nginx as ingress, please refer to the [Documentation](https://kubernetes.github.io/ingress-nginx/)


If you setup everything correctly you should see something like

```bash
❯ kubectl get pods -o wide -n ingress-nginx
NAME                                        READY   STATUS      RESTARTS   AGE   IP               NODE           NOMINATED NODE   READINESS GATES
ingress-nginx-admission-create-gzpvj        0/1     Completed   0          9d    10.42.0.106      erebe-server   <none>           <none>
ingress-nginx-admission-patch-hs457         0/1     Completed   0          9d    10.42.0.107      erebe-server   <none>           <none>
ingress-nginx-controller-5f89b4b887-5wxmd   1/1     Running     0          8d    195.154.119.61   erebe-server   <none>           <none>
```
with the IP of your ingress-nginx-controller being the ip of your main interface

```bash
erebe@erebe-server:~$ ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default
...
2: enp1s0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether 00:08:a2:0c:63:4e brd ff:ff:ff:ff:ff:ff
    inet 195.154.119.61/24 brd 195.154.119.255 scope global enp1s0
       valid_lft forever preferred_lft forever
```

```bash
erebe@erebe-server:~$ sudo ss -lntp | grep -E ':(80|443) '
LISTEN    0         128                0.0.0.0:80               0.0.0.0:*        users:(("nginx",pid=32448,fd=19),("nginx",pid=22350,fd=19))
LISTEN    0         128                0.0.0.0:80               0.0.0.0:*        users:(("nginx",pid=32448,fd=11),("nginx",pid=22349,fd=11))
LISTEN    0         128                0.0.0.0:443              0.0.0.0:*        users:(("nginx",pid=32448,fd=21),("nginx",pid=22350,fd=21))
LISTEN    0         128                0.0.0.0:443              0.0.0.0:*        users:(("nginx",pid=32448,fd=13),("nginx",pid=22349,fd=13))
LISTEN    0         128                   [::]:80                  [::]:*        users:(("nginx",pid=32448,fd=12),("nginx",pid=22349,fd=12))
LISTEN    0         128                   [::]:80                  [::]:*        users:(("nginx",pid=32448,fd=20),("nginx",pid=22350,fd=20))
LISTEN    0         128                   [::]:443                 [::]:*        users:(("nginx",pid=32448,fd=14),("nginx",pid=22349,fd=14))
LISTEN    0         128                   [::]:443                 [::]:*        users:(("nginx",pid=32448,fd=22),("nginx",pid=22350,fd=22))
```


to test that everything is working you can deploy those resources and check that you can access your `http://domain.name` with the list of files of the container displayed

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test
  labels:
    app: test
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: test
  template:
    metadata:
      labels:
        app: test
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      containers:
      - name: webserver
        image: python:3.9
        imagePullPolicy: IfNotPresent
        command: ["python"]
        args: ["-m", "http.server", "8083"]
        ports:
        - name: http
          containerPort: 8083
---
apiVersion: v1
kind: Service
metadata:
  name: test
spec:
  selector:
    app: test
  ports:
    - protocol: TCP
      port: 8083
      name: http
  clusterIP: None
  type: ClusterIP
---
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: test-ingress
  annotations:
    kubernetes.io/ingress.class: "nginx"
spec:
  rules:
  - http:
      paths:
      - path: /
        backend:
          serviceName: test
          servicePort: http

```

This deployment, will start a python simple HTTP server on port 8083 on host network, a service will reference this deployment and the ingress (the configuration for our reverse proxy) will be configured to point toward it on path `/`

To debug you can check
```bash
# To investigate python simple http server pod issue
kubectl describe pod test
# To see endpoints listed by the service
kubectl describe service test
# To see ingress issue
kubectl describe service test
# To check the config of nginx
kubectl exec -ti -n ingress-nginx ingress-nginx-controller-5f89b4b887-5wxmd -- cat /etc/nginx/nginx.conf
```

# CertManager with let's encrypt for issuing TLS certificates  <a name="letsencrypt"></a>

We have our reverse proxy working, now we want our k3s cluster to be able to generate on the fly certificates for our deployments. For that we are going to use the standard [CertManager](https://github.com/jetstack/cert-manager) with [let's encrypt](https://letsencrypt.org/fr/) as a backend/issuer.

to install it simply do a
```bash
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.0.4/cert-manager.yaml
```

to automate the deployment we are going to add it in the repository and add a few lines in our Makefile

```bash
k8s:
        ...
        kubectl apply -f k8s/cert-manager-v1.0.4.yml
```

You can verify the installation with
```bash
$ kubectl get pods --namespace cert-manager

NAME                                       READY   STATUS    RESTARTS   AGE
cert-manager-5c6866597-zw7kh               1/1     Running   0          2m
cert-manager-cainjector-577f6d9fd7-tr77l   1/1     Running   0          2m
cert-manager-webhook-787858fcdb-nlzsq      1/1     Running   0          2m
```

Once Cert-Manager is deployed we need to configure an Issuer that is going to generate valid TLS certificates. For that we are going to use the free let's encrypt !

To do that simply deploy a new resource on the cluster
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
  namespace: cert-manager
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: email@your_domain.name
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
```
It will tell cert manager, that we are going to use the acme HTTP challenge of let's encrypt and use nginx as ingress for that.
The issuer is configured for the whole cluster (with kind: `ClusterIssuer`) so it is going to
1. Watch on all namespaces for the annotation `cert-manager.io/cluster-issuer: "letsencrypt-prod"`
2. Request a challenge from let's encrypt to (re-)generate TLS certificate
3. Create a secret with those new certificate upon challenge success


In our Makefile
```bash
k8s:
        ...
        kubectl apply -f k8s/lets-encrypt-issuer.yml
```

**Warning**: Be sure that your DNS name is valid/pointing to the correct machine before doing that, as it is easy to be blacklisted/throttled by let's encrypt. Especially if you are using DNS challenge for getting wildcard certificates.

If you configured everything correctly editing our previous ingress and adding
a cluster issuer annotation, a TLS section in the spec and a host in the rules is enough.
```yaml
---
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: test-ingress
  annotations:
    kubernetes.io/ingress.class: "nginx"
    cert-manager.io/cluster-issuer: "letsencrypt-prod" #Here
spec:
  tls: # here
  - hosts:
    - domain.name
    secretName: test-tls
  rules:
  - host: domain.name # here
    http:
      paths:
      - path: /
        backend:
          serviceName: test
          servicePort: 8083
```

After applying the new version of the ingress, the cert manager should detect the annotation and launch a challenge. (You can check the pods for ACME challenge being spawned) and after a few minutes getting your TLS certificate deployed as a secret.

```
$ kubectl get secrets test-tls
```

If everything is ok, simply use your browser and visit `https://domain.name` to see our simple python backend being deployed with a valid TLS certificate !!!


# Mail Server with Postfix + Dovecot + Fetchmail + SpamAssassin <a name="mail"></a>

Now I am going to install a mail server on my machine with a few caveats.

I am not going to use this SMTP server as an outgoing mail server, because nowadays it supposes to setup and maintain DKIM, SPF, DMARC and even when I have done so, sometimes my emails were ending-up in spam.
The cost is not worth it, so I am using my registrar gandi.net SMTP server as relay to send my emails.

I am not going to enter into the details of how to configure postfix + dovecot + fetchmail + spamassassin as there are already plenty of guides available for that on the internet. My goal is to explain how I use Kubernetes to make them all work together.

For more information you can refer to my repository to look into the detail. The high level overview is :

* Cert-Manager issue valid TLS certificate that are used by dovecot and postfix
* Postfix is configured with virtual alias to allow emails from `*@my_domain.name`
* Postfix does not use any database (so no MySQL)
* Every mail are redirected to a single user, that run `procmail` with a custom program [hmailfilter](https://github.com/erebe/hmailfilter) to triage automatically my email (**Warning** procmail is since a few years unmaintained and contains CVEs)
* Emails are stored in the `maildir` format
* Dovecot and postfix communicate by sharing this single maildir by mounting the same hostPath volume in both container
* I don't tag my custom container images, GitHub action is configured on every push to rebuild the image of {postfix, dovecot} and to publish them under `latest`
* I use trunk deployment for my images. I simply delete the current pod and let it recreate itself with the use of `imagePullPolicy: Always` to get the latest version


So let's start, first update your MX DNS record to point to your server
```bash
@ 10800 IN MX 1 mail.erebe.eu.
@ 10800 IN MX 10 spool.mail.gandi.net.
@ 10800 IN MX 50 fb.mail.gandi.net.
```
In my setup I add my registrar SMTP server as a safety net in case my server is down. Fetchmail is configured to retrieve from it any emails it may have received for me.


Next step is to create a valid TLS certificate for both:
* Postfix as we want to support STARTTLS/SSL
* Dovecot, I only allow IMAPs and don't want self-signed certificate warning pop-ups

For that we simply use Kubernetes cert-manager and create a Certificate resource

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: dovecot-tls
spec:
  # Secret names are always required.
  secretName: dovecot-tls
  duration: 2160h # 90d
  renewBefore: 720h # 30d
  subject:
    organizations:
    - erebe
  # The use of the common name field has been deprecated since 2000 and is
  # discouraged from being used.
  isCA: false
  privateKey:
    algorithm: RSA
    encoding: PKCS1
    size: 2048
  usages:
    - server auth
    - client auth
  # At least one of a DNS Name, URI, or IP address is required.
  dnsNames:
  - mail.your_domain.name
  # Issuer references are always required.
  issuerRef:
    name: letsencrypt-prod
    # We can reference ClusterIssuers by changing the kind here.
    # The default value is Issuer (i.e. a locally namespaced Issuer)
    kind: ClusterIssuer

```

With that the cert-manager will issue a certificate under the secret `dovecot-tls` signed by let's encrypt.
After a few minutes, your secret will be available

```bash
❯ kubectl describe secret dovecot-tls
Name:         dovecot-tls
Namespace:    default
Labels:       <none>
Annotations:  cert-manager.io/alt-names: mail.erebe.eu
              cert-manager.io/certificate-name: dovecot-tls
              cert-manager.io/common-name: mail.erebe.eu
              cert-manager.io/ip-sans:
              cert-manager.io/issuer-group:
              cert-manager.io/issuer-kind: ClusterIssuer
              cert-manager.io/issuer-name: letsencrypt-prod
              cert-manager.io/uri-sans:

Type:  kubernetes.io/tls

Data
====
tls.crt:  3554 bytes
tls.key:  1679 bytes
```

after that we can inject those certificate in the container thanks to volumes in our deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dovecot
  labels:
    app: dovecot
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: dovecot
  template:
    metadata:
      labels:
        app: dovecot
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      containers:
      - name: mail
        image: erebe/dovecot:latest
        imagePullPolicy: Always
        ports:
        - containerPort: 993
        volumeMounts:
        - name: dovecot-tls
          mountPath: /etc/ssl/dovecot/
          readOnly: true
        - name: dovecot-users-password
          mountPath: /etc/dovecot/users/
          readOnly: true
        - name: mail-data
          mountPath: /data
      volumes:
      - name: dovecot-tls
        secret:
          secretName: dovecot-tls
      - name: dovecot-users-password
        secret:
          secretName: dovecot-users-password
      - name: mail-data
        hostPath:
          path: /opt/mail/data
          type: Directory
```

In my deployments:
* We are using host network
* All the data are stored on the host file system under `/opt/xxx` in order to easily backup it
* All the container use the same created user ID 1000 for writing data to avoid conflicting rights
* Password are stored as Kubernetes secrets and committed inside the repository thanks to sops

```yaml
apiVersion: v1
kind: Secret
metadata:
    name: dovecot-users-password
type: Opaque
stringData:
    users: 'erebe:{MD5-CRYPT}xxxxx.:1000:1000::::/bin/false::'
```

In the end, deploying dovecot from our makefile is a simple

```bash
dovecot:
        sops -d --output secrets_decrypted/dovecot.yml secrets/dovecot.yml
        kubectl apply -f secrets_decrypted/dovecot.yml
        kubectl apply -f dovecot/dovecot.yml
```

For postfix it is the same, and we are reusing the previous created TLS certificate for providing STARTTLS/SSL support for the SMTP server

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postfix
  labels:
    app: postfix
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: postfix
  template:
    metadata:
      labels:
        app: postfix
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      containers:
      - name: postfix
        image: erebe/postfix:latest
        imagePullPolicy: Always
        ports:
        - containerPort: 25
        volumeMounts:
        - name: dovecot-tls
          mountPath: /etc/ssl/postfix/
          readOnly: true
        - name: mail-data
          mountPath: /data
        - name: fetchmail
          mountPath: /etc/fetchmail
      volumes:
      - name: dovecot-tls
        secret:
          secretName: dovecot-tls
      - name: mail-data
        hostPath:
          path: /opt/mail/data
          type: Directory
      - name: fetchmail
        configMap:
          name: fetchmail
          items:
          - key: fetchmailrc
            path: fetchmailrc
```

our Makefile
```bash
postfix:
        sops -d --output secrets_decrypted/fetchmail.yml secrets/fetchmail.yml
        kubectl apply -f secrets_decrypted/fetchmail.yml
        kubectl apply -f postfix/postfix.yml
```
and for the fetchmail config
```
defaults:
timeout 300
antispam -1
batchlimit 100
set postmaster erebe

poll mail.gandi.net
        protocol POP3
        no envelope
        user "your_login" there
        with password "xxxx"
        is erebe here
        no keep
```

# Automating build and push of our images with GitHub actions <a name="build"></a>

When I do a change, I want my custom images to be rebuilt and push automatically in a registry.
To achieve it I rely on a 3rd party, [GitHub actions](https://github.com/features/actions) !

```yaml
#.github/workflows/docker-dovecot.yml
name: Publish Dovecot Image
on:
  push:
    paths:
    - 'dovecot/**'

jobs:
  buildAndPush:
    name: Build And Push docker images
    runs-on: ubuntu-latest
    steps:
      - name: Check out the repo
        uses: actions/checkout@v2
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v1
      - name: Login to Github container repository
        uses: docker/login-action@v1
        with:
          registry: ghcr.io
          username: ${{ github.repository_owner }}
          password: ${{ secrets.CR_PAT }}
      - name: Dovecot
        id: docker_build_dovecot
        uses: docker/build-push-action@v2
        with:
          context: dovecot
          file: dovecot/Dockerfile
          push: true
          tags: ghcr.io/erebe/dovecot:latest
      - name: Dovecot Image digest
        run: echo Dovecot ${{ steps.docker_build_dovecot.outputs.digest }}

```

When a file under `dovecot/**` is modified during a commit, the Github Actions CI will trigger the job that re-build the docker image and push it to the [GitHub container registry](https://github.com/features/packages).
I use GitHub container registry in order to centralize things as much as possible and avoid adding docker hub as another external dependencies.

The part left to do yet, is automatic deployment when a new image is build.
Ideally, I would like to avoid having to store my kubeconfig inside GitHub secrets and code an app that support web hook in order to trigger a new deployment. But for now I am still thinking of how to do that properly, so I am left to delete manually my pod to re-fetch the latest image until then ¯\\_(ツ)_/¯

# Automatic deployment with Webhook <a name="deployment"></a>

Next step is to automatically deploy new releases of my images/application. I chose to not automate the change in my infrastructure code (Kubernetes configs) as when I am doing those changes, I am already behind the screen touching this part of the code/repository, so deploying it is just a `make xxx` away.

In my case what I want to automate is the deployment of new release of my software. For example, when I am working on a project (not in this repository), I don't want to go back to this repository to bump something or do a `make xxx`. I just want to release of a new version of my application images and it being deployed automatically.

For that, I am going to put in place a webhook [thanks to this great project](https://github.com/adnanh/webhook). It will allow me to

 * Make automatic deployment possible while my kubernetes api-server is not reachable from internet
 * Centralize my deployment logic inside this repository
 * While making possible for external project to call this deployer with a simple HTTP call

**Warning**: If your kube-apiserver is reachable from internet and that you want to also automate the deployment of your infra, please use Skaffold. The tool have been made for that and allow streamlining things easily.

As I don't tag my personal images, I always use latest (an equivalent for prod if you want) my deployments are pretty simple.
1. Delete the current pod
2. Kubernetes will start a new one and pull the new image
3. Wait for the new pod to be running

```bash
    #!/bin/sh
    [[ -z "$1" ]] && exit 1
    app_name="$1"
    kubectl delete pod -n default -l app=${app_name}
    kubectl wait --for=condition=Ready --timeout=-1s -n default -l app=${app_name} pod
 ```

 So the only thing our deployer need is kubectl and access to the kube-api.

 Let's start by building the deployer image. As mentioned I am going to

  * Use [webhook](https://github.com/adnanh/webhook)
  * Add the kubectl image (sadly we can't pin the kubectl version with alpine due to the package being present only in testing))
  * Create a new user and use it to avoid my image/process running as root
  * Add a new github action to build and publish this new image

```
FROM almir/webhook:2.7.0
LABEL org.opencontainers.image.source https://github.com/erebe/personal-server

RUN adduser -D -u 1000 abc && \
    apk add --no-cache kubectl --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing

USER abc
```

The config of my webhook will live inside a ConfigMap. It will run my deploy script only if the `X-Webhook-Token` with the correct secret is present and pass as argument to the script the value of the variable `application_name` of the json payload.

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: webhook
data:
  hook.json: |
    [
      {
        "id": "deploy",
        "execute-command": "/data/deploy.sh",
        "command-working-directory": "/var/run/",
        "pass-arguments-to-command":
        [{
          "source": "payload",
           "name": "application_name"
        }],
        "trigger-rule": {
          "match": {
            "type": "value",
            "value": "__DEPLOYER_SECRET__",
            "parameter": {
              "source": "header",
              "name": "X-Webhook-Token"
            }
          }
        }
      }
    ]
  deploy.sh: |
    #!/bin/sh
    [[ -z "$1" ]] && exit 1
    app_name="$1"
    kubectl delete pod -n default -l app=${app_name}
    kubectl wait --for=condition=Ready --timeout=-1s -n default -l app=${app_name} pod
```

By default pods are not allowed to connect to the kubernetes-api and do operation on it for obvious security concern.

Thanks to [RBAC - Role Base Access Control](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) it is possible to define Role/User and give them access to certain operations on the kube-api.


```yaml
# Service account are our new "user"
apiVersion: v1
kind: ServiceAccount
metadata:
  name: deployer
---

# A role is an object where we can assign some access
# A role is specific to a single namespace. If you want cluster wide role, use ClusterRole instead of just Role
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: default
  name: deployer
rules:
- apiGroups: [""] # "" indicates the core API group
  resources: ["pods"] # Resources that we are allowed to access
  verbs: ["get", "watch", "list", "delete"] # Actions we allow on those objects
---

# A RoleBinding associate a Role to a User, in our case the "deployer" role, to the "deployer" ServiceAccount/User
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: deployer
  namespace: default
subjects:
- kind: ServiceAccount
  name: deployer
  namespace: default
roleRef:
  kind: Role
  name: deployer
  apiGroup: rbac.authorization.k8s.io
---
```

After that we only need to say that our deployment is done under our custom ServiceAccount instead of the default one
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webhook
  labels:
    app: webhook
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: webhook
  template:
    metadata:
      labels:
        app: webhook
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      serviceAccountName: deployer # HERE
....
```

Once everything is set-up, we only need to add in our github action a call to curl to trigger a deployment of our new release
```yaml
....
      - name: Dovecot
        id: docker_build
        uses: docker/build-push-action@v2
        with:
          context: dovecot
          file: dovecot/Dockerfile
          push: true
          tags: ghcr.io/erebe/dovecot:latest
...
      - name: Trigger deployer # Here to deploy
        run: |
          payload='{ "application_name": "dovecot", "image_digest": "${{ steps.docker_build.outputs.digest }}", "image_tag": "latest" }'
          token='X-Webhook-Token: ${{ secrets.WEBHOOK_SECRET }}'
          curl -X POST -H 'Content-Type: application/json' -H "${token}"  -d "${payload}" https://hooks.erebe.eu/hooks/deploy
```

Final version of the deployment is [here](https://github.com/erebe/personal-server/blob/master/services/webhook/webhook.yml)


# Hosting your own cloud with Nextcloud <a name="cloud"></a>

[Nextcloud](https://nextcloud.com/) allows you to get a dropbox/google drive at home and many more feature if you want to (caldav, todos, ...). The Web UI is working well and they provide also great mobile application for IOs/Android.
With an extra module we can mount external storage (sftp, ftp, s3, ...) which allows to have nextcloud as a central point for managing our data.

**Warning** If you only care about storing your data, buying a NAS or paying for DropBox/OneDrive/GoogleDrive plan will be much worth of your bucks/time.

To deploy nothing fancy, it is a standard deployment with its ingress. The only specificities are:

  * We add nginx annotation to increase body max payload `nginx.ingress.kubernetes.io/proxy-body-size: "10G"`
  * We override the default configuration of the nginx bundled inside the image with a ConfigMap in order to make it behave well with our ingress



```yaml
apiVersion: v1
kind: ConfigMap
metadata:
    name: nextcloud-nginx-siteconfig
data:
    default: |
      upstream php-handler {
          server 127.0.0.1:9000;
      }
      server {
          listen 8083;
          listen [::]:8083;
          server_name cloud.erebe.eu;
...
```

The deployment
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nextcloud
  labels:
    app: nextcloud
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: nextcloud
  template:
    metadata:
      labels:
        app: nextcloud
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      containers:
      - name: nextcloud
        image: linuxserver/nextcloud:amd64-version-20.0.0
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 8083
        volumeMounts:
        - name: data
          mountPath: /data
        - name: config
          mountPath: /config
        - name: nginx-siteconfig
          mountPath: /config/nginx/site-confs
      volumes:
      - name: nginx-siteconfig
        configMap:
          name: nextcloud-nginx-siteconfig
      - name: data
        hostPath:
          path: /opt/nextcloud/data
          type: Directory
      - name: config
        hostPath:
          path: /opt/nextcloud/config
          type: Directory
---
apiVersion: v1
kind: Service
metadata:
  name: nextcloud
spec:
  selector:
    app: nextcloud
  ports:
    - name: http
      port: 8083
      protocol: TCP
  type: ClusterIP
  clusterIP: None

---
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: nextcloud-ingress
  annotations:
    kubernetes.io/ingress.class: "nginx"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "10G"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  tls:
  - hosts:
    - cloud.erebe.eu
    secretName: nextcloud-tls
  rules:
  - host: cloud.erebe.eu
    http:
      paths:
      - path: /
        backend:
          serviceName: nextcloud
          servicePort: http

```




# Backups <a name="backup"></a>

My backups are simplistic, as I store all the data under `/opt` on the host machine and that I am not running any dedicated database.
The Backup of the data consist of:
1. Running a cron-job every night inside Kubernetes that is spawning a container
2. Mounting the whole `/opt` folder inside the container as a volume
3. Creating a tar of `/opt`
4. Pushing the tarball to the ftp server that my hosting company provide me
5. Pinging [https://healthchecks.io](https://healthchecks.io/) in order to message me on whatsapp if a I miss backups

```yaml
apiVersion: batch/v1beta1
kind: CronJob
metadata:
  name: backup
spec:
  schedule: "0 4 * * *"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 1
  failedJobsHistoryLimit: 2
  jobTemplate:
    spec:
      template:
        spec:
          hostNetwork: true
          dnsPolicy: ClusterFirstWithHostNet
          containers:
          - name: backup
            image: alpine
            args:
            - /bin/sh
            - -c
            - apk add --no-cache lftp curl; tar -cvf backup.tar /data; lftp -u ${USER},${PASSWORD} dedibackup-dc3.online.net
              -e 'put backup.tar -o /backups/backup_neo.tar; mv backups/backup_neo.tar backups/backup.tar; bye' && curl https://hc-ping.com/xxxxx
            env:
            - name: USER
              valueFrom:
                secretKeyRef:
                  name: ftp-credentials
                  key: username
            - name: PASSWORD
              valueFrom:
                secretKeyRef:
                  name: ftp-credentials
                  key: password
            volumeMounts:
            - name: data
              mountPath: /data
          restartPolicy: OnFailure
          volumes:
          - name: data
            hostPath:
              path: /opt
              type: Directory

```

# [TODO] Monitoring with netdata <a name="monitoring"></a>

[netdata](https://github.com/netdata/netdata)

# Virtual Private Network with Wireguard <a name="wireguard"></a>

My next step is to setup a VPN with [wireguard](https://www.wireguard.com/) to :
* Remove the access of the kube api server from internet
* Connect machines (Raspberry Pi) that can't be reached from internet
* Manage my Raspberry Pi as simple nodes inside the k3s cluster
* Route my traffic toward a safe network when in café, airports, etc (almost never...)

We are not going to install WireGuard a Kubernetes deployment as it requires a kernel module in order to work correctly. The only way is to install it directly on the host machine !

Follow this [guide](https://www.cyberciti.biz/faq/debian-10-set-up-wireguard-vpn-server/) in order install and configure WireGuard for Debian.

The only change I made is to add `postUp` and `postDown` rules to the `wg0.conf` in order to forward and masquerade traffic that are targeting network outside the VPN. This setup allows me to route all my local machine traffic through the VPN (i.e: When using my phone) when I want to.

```ini
#wg0.conf
[Interface]
Address = 10.200.200.1/24
ListenPort = 995
PrivateKey = __SERVER_PRIVATE_KEY__
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o enp1s0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o enp1s0 -j MASQUERADE

[Peer]
PublicKey = __RASPBERRY_PUBLIC_KEY__
AllowedIPs = 10.200.200.2/32

[Peer]
PublicKey = __PHONE_PUBLIC_KEY__
AllowedIPs = 10.200.200.3/32

[Peer]
PublicKey = __LAPTOP_PUBLIC_KEY__
AllowedIPs = 10.200.200.4/32

```

On my phone for example, to route all the traffic trough the VPN. I am going to have a setup like this one
```ini
[Interface]
# Client
PrivateKey = xxx
Address = 10.200.200.2/32

[Peer]
# Server
PublicKey = xxxx
## Allow all the traffic to flow through the VPN
AllowedIPs = 0.0.0.0/0
```

The make file to automate the deployment of the config
```bash
wireguard:
        sops exec-env secrets/wireguard.yml 'cp wireguard/wg0.conf secrets_decrypted/; for i in $$(env | grep _KEY | cut -d = -f1); do sed -i "s#__$${i}__#$${!i}#g" secrets_decrypted/wg0.conf ; done'
        ssh ${HOST} "cat /etc/wireguard/wg0.conf" | diff  - secrets_decrypted/wg0.conf \
                || (scp secrets_decrypted/wg0.conf ${HOST}:/etc/wireguard/wg0.conf && ssh ${HOST} systemctl restart wg-quick@wg0)
        ssh ${HOST} 'systemctl enable wg-quick@wg0'
```

# Bypass firewalls with WsTunnel <a name="wstunnel"></a>

Sometimes is it not possible to connect to my VPN due to some firewalls, because Wireguard uses UDP traffic and it is not allowed, or the port 995 (POP3s) I bind it on is forbidden.

To bypass those firewalls and allow me to reach my private network I use [WsTunnel](https://github.com/erebe/wstunnel), a websocket tunneling utility that I wrote. Basically, wstunnel leverage Websocket protocol that is using HTTP in order to tunnel TCP/UDP traffic through it.
With that, 99.9% of the time I can connect to my VPN network, at the cost of 3 layer of encapsulation (data -> WebSocket -> Wireguard -> Ip) :x

Check the [readme](https://github.com/erebe/wstunnel/blob/master/README.md) for more information

```bash
# On the client
wstunnel -u --udpTimeout=-1 -L 1995:127.0.0.1:995 -v ws://ws.erebe.eu
# in your wg0.conf point the peer address to 127.0.0.1:995 instead of domain.name
```
On the server, the only specificity are on the ingress.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wstunnel
  labels:
    app: wstunnel
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: wstunnel
  template:
    metadata:
      labels:
        app: wstunnel
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      containers:
      - name: wstunnel
        image: erebe/wstunnel:latest
        imagePullPolicy: Always
        args:
        - "--server"
        - "ws://0.0.0.0:8084"
        - "-r"
        - "127.0.0.1:995"
        ports:
        - containerPort: 8084
---
apiVersion: v1
kind: Service
metadata:
  name: wstunnel
spec:
  selector:
    app: wstunnel
  ports:
    - protocol: TCP
      port: 8084
      name: http
  clusterIP: None
  type: ClusterIP
---
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: wstunnel-ingress
  annotations:
    kubernetes.io/ingress.class: "nginx"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "1800"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "1800"
    nginx.ingress.kubernetes.io/connection-proxy-header: "upgrade"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  tls:
  - hosts:
    - ws.erebe.eu
    secretName: wstunnel-tls
  rules:
  - host: ws.erebe.eu
    http:
      paths:
      - path: /
        backend:
          serviceName: wstunnel
          servicePort: http
```

# Installing K3S on our Raspberry Pi using your Wireguard VPN <a name="raspberry"></a>

I want my Raspberry Pi that is living inside my home network and not reachable from internet to be manageable like a simple node inside the Kubernetes cluster. For that I am going to setup Wireguard on my Raspberry Pi and install the k3s agent on it.

1. Installation Raspbian on your raspberry - [Tutorial](https://www.raspberrypi.org/documentation/installation/installing-images/)
2. Setup Wireguard on the raspberry - [Tutorial](https://www.sigmdel.ca/michel/ha/wireguard/wireguard_02_en.html#installing_wg_raspbian)
3. Configure Wireguard
```ini
[Interface]
PrivateKey = xxx
## Client ip address ##
Address = 10.200.200.2/32

[Peer]
PublicKey = xxxx
AllowedIPs = 10.200.200.0/24
## Your Debian 10 LTS server's public IPv4/IPv6 address and port ##
Endpoint = domain.name:995

##  Key connection alive ##
PersistentKeepalive = 20
```
5. Start wireguard and test it is working properly
6. On the `/boot/cmdline.txt` of the Raspberry Pi add those 2 boot options
```bash
cgroup_memory=1 cgroup_enable=memory
```
7. Reboot the raspberry
8. On the server edit `/etc/systemd/system/k3s.service` and add the argument
```
--advertise-address 10.200.200.1
```
9. Install k3S on the raspberry
```bash
# ssh on the raspberry, endpoint should be the ip of the server on the VPN network
# token can be found on the server at cat /var/lib/rancher/k3s/server/token
curl -sfL https://get.k3s.io | K3S_URL=https://10.200.200.1:6443 INSTALL_K3S_EXEC="--node-ip 10.200.200.2 --node-taint 'kubernetes.io/hostname=raspberrypi:NoSchedule'" K3S_TOKEN="xxxx" sh -

# --node-ip is to force using interface of wireguard to communicate with the node
# --node-taint is to disallow random container to end up on the raspberry, a toleration need to target it specifically
```
9. Check that your raspberry is in Ready state with its IP

# Deploying PiHole on your Raspberry Pi <a name="pihole"></a>

We have our raspberry Ready to use now inside our Kubernetes cluster.
It is time now to use it by deploying [PiHole](https://pi-hole.net/) as a DNS server inside our home local network.
PiHole allows blocking trackers by not responding to DNS requests. It is like having ad-block on your network instead of your browser.

This is a standard deployment, with only 3 specificity:

* We need to set the container in privileged mode as it needs to bind on port 53 (DNS)
```yaml
        securityContext:
          privileged: true
```
* It has a `nodeAffinity` and a toleration for our `taint` in order to allow and force the deployment on the raspberry
```yaml
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.io/hostname
                operator: In
                values:
                - raspberrypi
...
      tolerations:
      - key: "kubernetes.io/hostname"
        operator: "Equal"
        value: "raspberrypi"
        effect: "NoSchedule"
```

* We had another toleration for the state `unreachable` to let the container live on the raspberry even if we lose connectivity with the cluster.
  The pihole container will be deployed and will stay there until manually deleted
```yaml
      tolerations:
      - key: "node.kubernetes.io/unreachable"
        operator: "Exists"
        effect: "NoExecute"
```

Full YAML
```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pihole
  labels:
    app: pihole
spec:
  replicas: 1
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
  selector:
    matchLabels:
      app: pihole
  template:
    metadata:
      labels:
        app: pihole
    spec:
      hostNetwork: true
      dnsPolicy: "None"
      dnsConfig:
        nameservers:
        - 127.0.0.1
        - 1.1.1.1
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.io/hostname
                operator: In
                values:
                - raspberrypi
      containers:
      - name: pihole
        image: pihole/pihole:v5.1.2
        imagePullPolicy: IfNotPresent
        env:
        - name: TZ
          value: "Europe/Paris"
        - name: WEBPASSWORD
          value: "pihole"
        - name: CONDITIONAL_FORWARDING
          value: "true"
        - name: CONDITIONAL_FORWARDING_IP
          value: "192.168.1.254"
        - name: CONDITIONAL_FORWARDING_DOMAIN
          value: "lan"
        ports:
          - containerPort: 80
            name: http
            protocol: TCP
          - containerPort: 53
            name: dns
            protocol: TCP
          - containerPort: 53
            name: dns-udp
            protocol: UDP
        securityContext:
          privileged: true
        volumeMounts:
        - name: pihole-etc-volume
          mountPath: "/etc/pihole"
        - name: pihole-dnsmasq-volume
          mountPath: "/etc/dnsmasq.d"
      tolerations:
      - key: "kubernetes.io/hostname"
        operator: "Equal"
        value: "raspberrypi"
        effect: "NoSchedule"
      - key: "node.kubernetes.io/unreachable"
        operator: "Exists"
        effect: "NoExecute"
      volumes:
      - name: pihole-etc-volume
        hostPath:
          path: /opt/pihole/etc
          type: Directory
      - name: pihole-dnsmasq-volume
        hostPath:
          path: /opt/pihole/dnsmasq
          type: Directory
```


# Conclusion <a name="conclusion"></a>

* Everything is automated and idempotent
   * Installation of the machine
   * DNS
   * Reverse proxy
   * Certificate generation
   * docker image build
* Everything is centralized inside the git repository
   * Secrets are not separated from the code and derived from a GPG key
   * Configuration and deployment are together thanks to container and kubernetes
   * Deployment can be triggered from the makefile
   * Common way to package and deploy system package and my own projects
* A single interface/control plane to control several machines
   * Container allow each component to be isolated
   * Kubernetes allow to manage multiple servers and provide a clean interface
   * [k9s](https://k9scli.io/) to get a simple/intuitive command center
   * [skaffold](https://skaffold.dev/) for when I am developing



# If you want more Freedom <a name="freedom"></a>

* Host the machine at Home, if you have fiber you may have more bandwidth than a provider
* Manage dkim to not rely on the SMTP relay
* Host Gitlab to avoid relying on Github for git
    * Can be used to mirror your github repository
    * Can be used to have your own git actions
    * Can be used to have your own Docker repository
    
    
    
# Epilogue: 2023 update <a name="2023"></a>

It has been 2 years now that I wrote this guide, so I thought it was time for an update and give back some feedbacks now that I earned the benefit of hinsights.

## Gpg key Vs Age and Security in general <a name="2023_security"></a>

A lot of people ask me why I don’t talk about [Age](https://github.com/FiloSottile/age) `a simple, modern and secure file encryption tool, format, and Go library`. To be honest I was not knowing age before starting this guide and discovered it when the maintainer contacted me. I gave it a shot at the time, but even if the idea of providing something simpler to use than GPG to ensure authenticity was appealing to me, I was sat back due to the lack of integration with the rest of the ecosystem/tools. I gave it an other shot this year, and even if the status improved a lot, it is not possible yet to replace GPG for all use cases it covers.

To give you some examples, I use my GPG key coupled with a Yubikey to:

* Encrypt my files/secrets
* Sign my commits on git
* Provide ssh key attached to my ssh-agent
* 2FA device to authentificate me

To this day for example, you [can’t sign your git commit](https://github.com/FiloSottile/age/discussions/372) with an age key. So even if setting up a GPG key on a Yubikey can be involving, since I have done it, I never had to touch it again. So in term of maintainability and day to day simplicity GPG+Yubikey is still a no brainer for me.

And to be honest, for me the big problem that is not solved with GPG and age, is revocation. My keys never got lost/stolen yet?, but some day it will happen and in all the cases with GPG/Yubikey/Age, it will be an hasslle to traceback every site and revoke everything manually. Or re-crypt every file and erase them from history, if that even possible.

There is still, to my knowledge, no protocol/central place to say, please this device/key might be compromised revoke it and never allow it again.

I don’t consider myself a security expert, not even a security lover, for me it is just a necessary pain so I want it to be simple to use daily and be fool proof. To avoid being locked-out of my accounts in case I lose access to my Yubikey, I bought an account to [Bitwarden](https://bitwarden.com/) for 10$ a year and always use TOTP for 2FA in addition of my Yubikey.

So to sum-up my today security is still, GPG with a Yubikey coupled with TOTP (bitwarden) as a fallback in case I lose access to one of my devices. With this setup I never felt limited in any way, nor felt it was too cumbersome to use daily and is low maintenance so far. 
But hey, the real challenge will arise when I am going to lose one of my authentication factor ¯\_(ツ)_/¯

## Maintainability <a name="2023_maintenability"></a>

As you may have understood now, one of my requirements is low maintainability. I don’t have the luxury nowadays to throw full consecutive weekends into some side projects. Don’t get me wrong, a lot of my setups are there for me to learn some new stuff and I still does it out of passion, but I want to choose when I am available to poor those hours into the projects. I don’t want to have to spend this time because something broke, or because the stuff is flaky and I need to attend to it to make it back alive and use it. 

With this requirement, and even if in my mind nothing beat the maintainability/simplicity of a single machine with debian on it, I couldn’t have been more pleased by this current setup.

I went from machines were everything were setup by hand and after a few months/year forgetting how it was installed and how to modify/upgrade it. Until one day the machine goes out of life, and you have to re-setup everything again by hand. This time you said, ok time to use some config management, and decide to settle using ansible, but here again after a few months/year you can’t re-setup your machine because your python environment/venv is fucked up, some library have been updated and are not compatible anymore, and you spend more time attending to your playbook every time you want to do something than doing the real thing that lend you here in the fist place.

### What are the things that make this setup great in term of maintainability from my personnel use:
 
* Everything is centralized in a single repository, which is the source of truth
    * Secrets are stored along the code,  no other dependencies are required. It has been a big hassle for me before to have secrets in a different place
    * Easier to automate, update, scripts things, backups, all the git ops flow things
    * Documentation, the readme which is at first a tutorial was helping me remembering commands and how easy it was to execute some actions. Lowering my biais of if I don’t remember, it should be difficult/take time so I don’t want to do it.


* Not going full blown with devops tools
    * It means no terraform and deciding to setup some easy/long lived stuff by hand/ui instead of relying on a more complex tool that need to be updated/attenteded
    * It means no config management, and instead relying of Make, even if today I would use [just](https://github.com/casey/just) ) while keeping the key idea of idempotency 
    * It means no helm and relying only on kubectl for my own installation, as I don’t need all the feature of it
    * Usally devops tools evolve quickly and from my experience require daily practice for them to stay alive. They don’t usually like to be used once in a while, something just need to break in the middle after few months without usage


* Having a CI to automate everything
    * This one is thanks to github, but this is the first time that I have a CI integrated into my setup as before it was more a professional thing. Thanks to the democratization and lowering the access bar from Git providers to CI, this make this setup a breeze to use.
    * Git + CI + [webhook](https://github.com/adnanh/webhook) make a super smooth workflow.


* A single control plane with Kubernetes and K3s
    * I don’t have anymore only a single machine to monitor in my setup (more on that later), and it is really handy to be able to connect to my kubernetes cluster and see the well being of all my deployments/applications at once, where ever they run on.
    * K3s as proved itself to be super stable and never let me down once in those 2 years. Upgrading it to a newer version as been as easy as running a single command on every machines connected to the cluster

So to sumarrize what make things easier in my life are, simplicity to use (k3s may not fit to that to some but I use it daily at work so thats ok to me) so I don’t have to remember how to use the tools/do stuff, central point so I get started quickly and don’t spend time looking for what I need, automation so I don’t spend time looking how to build this app again, or how to re-setup/deploy it.

### What I would like to improve in term of maintainability ? 

First of all, even if everything is centralized in the git repository, re-building/upgrading everything is split across multiple dockerfile/yaml file/makefile, and I think I fail when I need to answer those question: If a new openssl vulnerability patch got released on november 1rst, how many of my apps are affected/need to be rebuild with the patch ?

I still dream of an apt-get update & apt-get upgrade across all my machines/containers/app, and I still think I need a big button where I am able to rebuild and update everything easily.


## Extensibility <a name="2023_extensibility"></a>

The combinaison of wireguard + kubernetes make everything extensible easily by default, while still keeping the same central point/control plane. 
This year I bought a flat, and I have now some place to host more things at home. I decided to buy a [mini-pc](https://www.amazon.fr/gp/product/B08PBJ2LPR/ref=ppx_yo_dt_b_asin_title_o00_s00?ie=UTF8&psc=1) and a [storage bay](https://www.amazon.fr/gp/product/B084Z3Y3CG/ref=ppx_yo_dt_b_asin_title_o02_s00?ie=UTF8&psc=1) in order to build myself a NAS.
On the mini-pc I run [Proxmox](https://www.proxmox.com/en/) that in turn run ZFS and a VM attached to my kubernetes cluster that run [Minio](https://github.com/minio/minio) to have an S3/backups storage at home.

All this complexity, the fact that the machines run on a different network, by different operating systems, are in the end abstracted away thanks to wireguard to flatten the network, and kubernetes to centralize the compute.
I really enjoyed that this setup let me started easily with a single machine, and allowed me to grow without pain and changing anything in the way how I manage the whole.

### What I would like to improve in term of extensibility ? 

For now nothing, I quite happy with what I have. I never felt the need to have an extensible data layer, maybe it will come one day, but as I don’t have many photos/videos/movies, my data need is quite low at the moment.


## Observability <a name="2023_observability"></a>

I still don't monitor my machines, beside the helthchecks.io alerts configured to page me on whatsapp for my backups and ping of external services.
At first I thought about setting up netdata/or a grafana + prometheus, but so far, I never felt the need to investigate what was going on.
Using k9s + ssh to monitor/have a glance of my machines status, provided to be enough.
Maybe one day I will feel the need, but with my low usage, hardware is robust enough for me to trust the system.

# 2023 Conclusion <a name="2023_conclusion"></a>

After 2 years, I am pretty happy with this setup. I picture it as secure, simple to use, robust, maintenable and extensible.
But it is not all white, and for the years to come, I would like to improve the few things below
1. Force me to revoke one of my 2FA device in order to measure/learn the pain to do it and avoid fearing such event to occur.
2. Improving maintenability by automating upgrade/re-build of everything. So far I only update when I decide too, but would like to ease this process and centralize version of everything
3. Reduce my reliance on a 3rd party CI (github), everything can work without it, but it is too convenient, so I would like to internalize it (GitlabCI ? Drone ? Will see)
4. Ease integration ? I can't use on the shelf tool and need to re-integrate every myself, which is sometime a pain, as it is not as easy as start this container in portainer. But hey, it is the purpose of this project to do it myself to learn ¯\_(ツ)_/¯

