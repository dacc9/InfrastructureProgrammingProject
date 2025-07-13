#!/bin/bash

eval "$(ssh-agent -s)"
ssh-add ../../../ssh_keys/project_key

ansible-playbook shutdown.yml -i ../../inventory.ini

ssh-add -d ../../../ssh_keys/project_key
kill $SSH_AGENT_PID
