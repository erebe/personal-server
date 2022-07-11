#!/bin/sh

set -ex

chown -R erebe:erebe /data 
crond -l 8 -d 8 
dovecot -F
