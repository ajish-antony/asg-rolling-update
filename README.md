# ASG Rolling Update Using Dynamic Inventory
## (Continous Deployment via Jenkins and Ansible)

[![Build Status](https://travis-ci.org/joemccann/dillinger.svg?branch=master)](https://travis-ci.org/joemccann/dillinger)

Here is a project with a rolling update for the auto-scaling group. Initially, I will provide a basic idea of the infrastructure implemented here. Developers are provided with a Central Github repository for updating the files in the website application. They will be pushing the codes to the repository and once the repository is updated, the new changes should reflect in the website application automatically. 

On the Infra side, configured an Autoscaling group with launch configuration having the user-data to fetch the contents from the Github repository. So for the new instances, spinning up will be provisioned with the application data. At the same time for managing the traffic, a load balancer has been configured. 

Here the reason for ASG rolling update implementation was that the project is running somewhat in the testing phase. There were so many builds ongoing from the development side and the requirement was such that the changes made by the developers should only reflect in the current instances (no need for new instances spin-up with the update). 

#### Issues In Normal Scenario

- As in the normal scenario, new instances will be spin-up once the Launch Configurations are updated. As I have stated, it's in a testing phase and there were multiple builds, so there will be multiple instances spinning up and will be causing a rise in the billing. 

- Another concern is that there were maybe a high number of tasks to run as part of the new update, so for updating these tasks, instances will be taken out of service and will be made available only once the whole task is completed, which will affect the application.

#### Rolling Update & Continous Deployment

- To overcome the issues mentioned above here I have implemented an auto-scaling rolling update via Ansible playbook. So here the only task will be updating one per instance. It means that one instance will be taken out from the load balancer and that new updates will be added to the same. Once everything completes, it will be added back to the load balancer. Then moves forward with the next one in the Autoscaling group. So there will not any service disruption. 

- As mentioned, the new instances will not be spin-up, that they will be updating only in the existing Instances. So it avoids the billing Issue.

- For automating the whole process, here I provided a Jenkins server for the continuous deployment procedure. Once the developer pushes the codes to the Github, Jenkins Server will be triggered via the webhook configured. So the build will take place and will be running the ansible-playbook to update the changes.


## Features

- Auto-scaling Rolling update via Ansible Playbook
- Continuous Deployment with Jenkins, makes jobs much simpler
- Dynamic Inventory Is configured, so no need for hosts
- IAM Role has been updated to the Ansible Master, so no need to share the creds


## Architecture

![
alt_txt
](https://i.ibb.co/27rS5FP/asg-rolling-7.jpg)



## Pre-Requests
- Basic Knowledge in AWS services, Ansible, Jenkins
- IAM Role with necessary privileges
- Ansible should be Installed on the Master Machine
>Ansible Installation refer - [Installation Steps](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) 
- IAM role should be attached to the Ansible Master 
> IAM Role Creation refer - [IAM Role Steps](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create.html)

## Modules Used
- yum
- pip
- ec2_instance_info
- add_hosts
- seiral
- file
- git
- pause
- debug
- ansible-vault

## Ansible Playbook

- Here below provided is the Ansible playbook which will be running the tasks as mentioned earlier.  

```sh
---
- name: "Rolling Update For ASG"
  hosts: localhost
  vars_files:
    - app.vars
  tasks:
  
    - name: "Installing pip"
      yum:
        name: pip
        state: present
    
    - name: "Installing boto3"
      pip:
        name: boto3
        state: present
    
    - name: "Fetching Ec2 ASG Details"
      ec2_instance_info:
        region: "{{region}}"
        filters: 
          "tag:aws:autoscaling:groupName": "{{tag_name}}"
          instance-state-name: ["running"]
      register: asg_instances
    
    - name: "Dynamic Inventory For Autosclaing Ec2"
      add_host: 
        name: "{{item.public_ip_address}}"
        groups: "asg"
        ansible_host: "{{item.public_ip_address}}" 
        ansible_port: 22
        ansible_user: "ec2-user"
        ansible_ssh_private_key_file: "{{private_key}}"
        ansible_ssh_common_args: "-o StrictHostKeyChecking=no"
      with_items:
        - "{{asg_instances.instances}}"
    
- name: "Deploying Website From GitHub to ASG"
  become: true
  hosts: asg
  gather_facts: false
  serial: 1
  vars_files:
    - app.vars
  tasks:
    - name: "Installing the Git Packages"
      yum:
        name: 
          - httpd
          - git
        state: latest
    
    - name: "Creating the Clone Directory"
      file:
        path: "{{clonDir}}"
        state: directory
    
    - name: "Cloning the Git Repository"
      git:
        repo: https://github.com/ajish-antony/ansible-website.git
        dest: "{{clonDir}}"
      register: clone_status

    - name: "Disabling Health Check"
      when: clone_status.changed
      file:
        path: /var/www/html/health.txt
        state: file
        mode: 000
    
    - name: "Offloading Ec2 Instance"
      when: clone_status.changed
      pause: 
        seconds: "{{health_time}}"
        prompt: "Please Hold on off loading Is going On"

    - name: "Copying the contents from the Clone Directory to Ec2 Instances"
      when: clone_status.changed
      copy:
        src: "{{clonDir}}"
        dest: /var/www/html/
        remote_src: true
    
    - name: "Restarting/Enabling httpd"
      when: clone_status.changed
      service:
        name: httpd
        state: restarted
        enabled: true
    
    - name: "Enabling the Health Check"
      when: clone_status.changed
      file:
        path: /var/www/html/health.txt
        state: file
        mode: 0644

    - name: "Loading Back the Ec2 instance"
      when: clone_status.changed
      pause:
        seconds: "{{health_time}}"
        prompt: "Please hold on Loading back the Ec2 Instance"
```
- Update the variables with the required values in the file "app.vars". Consider as a sample provided below.

```sh
---
region: "us-east-1"
tag_name: "asg-01"
private_key: "work.pem"
health_time: 25
gitRepository: "https://github.com/ajish-antony/ansible-website.git"
clonDir: /var/git/
```
Also here I have provided sample user data for the instances if creating for the first time in the autoscaling or can be made use for the AMI creation.

```sh
#!/bin/bash
yum install httpd php git -y
git clone https://github.com/ajish-antony/ansible-website.git /var/git/
cp -pr /var/git/* /var/www/html/
service httpd restart
chkconfig httpd on
```

## Jenksin Server Setup

- For Jenkins Installation follow the commands given below

```sh
amazon-linux-extras install epel -y
yum install java-1.8.0-openjdk-devel -y
wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io.key
yum -y install jenkins
systemctl start jenkins
systemctl enable jenkins
```

> http://< serverIP >:8080

## CI/CD - Jenkins Configuration

- Configuration proceeds with the installation of the plugin "Ansible". For the same navigate to

>  Manage Jenkins --> Manage Plugins

![
alt_txt
](https://i.ibb.co/yhjFtVc/1-ansible-install.png)

> From the new window, search for the Ansible plugin from the Available section

![
alt_txt
](https://i.ibb.co/Nt49zLC/2-ansible-install.png)

> Once the installation completes, configure the ansible, for the same navigate to Global Tool Configuration

![
alt_txt
](https://i.ibb.co/d2kMr85/3-ansible-configure.png)

> Then updates with the name and executable path for the ansible as provided below

![
alt_txt
](https://i.ibb.co/tPzL1r0/4-ansibel-configure.png)

> Then move forwards with the creation of the job in Jenkins and proceeds with the selection of Freestyle Project

![
alt_txt
](https://i.ibb.co/nghqhx7/5-project.png)

> As here we are using Github as the source code management, provides with the GitHub Repository name

![
alt_txt
](https://i.ibb.co/LkxmBm9/Screenshot-1.png)

> Apply build procedure to invoke the ansible-playbook

![
alt_txt
](https://i.ibb.co/xfd4nDy/Screenshot-2.png)

> Update the ansbilbe palybook file location

![
alt_txt
](https://i.ibb.co/DGk2kMt/Screenshot-3.png)

> We can provide additional security for the ansible file with ansible-vault. It can be updated here as provided below.

![
alt_txt
](https://i.ibb.co/vdNmt7r/Screenshot-4.png)

> Here I have provided a password for the main.yml file, So I have chosen secret text as below and updated the vault password. 

![
alt_txt
](https://i.ibb.co/Y7j0h1S/Screenshot-6.png)

![
alt_txt
](https://i.ibb.co/vsL9GXk/Screenshot-8.png)

> Further needs to update the Github webhook to integrate with the Jenkins. For the same update the Jenkins server IP as provided below in the webhook URL.

- (http://< jenkins-server-IP >:8080/github-webhook/)

![
alt_txt
](https://i.ibb.co/tHPHyqQ/Screenshot-9.png)

> Once added the webhook in the GitHub, updated the Jenkins configuration as such to trigger when GitHub pushes. 

![
alt_txt
](https://i.ibb.co/sJXSF0j/Screenshot-11.png
)

## Conclusion

Here was the project that has managed to deploy in the ASG rolling method with the help of the Ansible-playbook. And the whole process has been automated with the help of Jenkins.



### ⚙️ Connect with Me

<p align="center">
<a href="mailto:ajishantony95@gmail.com"><img src="https://img.shields.io/badge/Gmail-D14836?style=for-the-badge&logo=gmail&logoColor=white"/></a>
<a href="https://www.linkedin.com/in/ajish-antony/"><img src="https://img.shields.io/badge/LinkedIn-0077B5?style=for-the-badge&logo=linkedin&logoColor=white"/></a>
