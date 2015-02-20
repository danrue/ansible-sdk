ansible-sdk
===========

### *The SPS Ansible Development Kit*

## Functions

### Build Role Artifacts

Build an artifact for a role that can be used to distribute the role 
to statisfy requirements thereupon.

`ansible-sdk role_artifact`

This should be executed from the directory containing `roles/`, and will 
build an artifact for each subdirectory in `roles/`.  The name of each artifact will 
be taken from the name of the subdirectory under `roles/`.

### Build Playbook Artifact

Build an artifact for the current directory's playbook and place into 
`build/`.  

`ansible-sdk playbook_artifact`

This should be executed from the top level playbook directory.  The name of 
the artifact will be taken from the name of the directory containing the playbook.  

### Publish artifact 

Publish an artifact at a given path to s3.  

<code>ansible-sdk publish_artifact <i>path-to-artifact</i></code>

By default, bucket `sps-build-deploy` and 
`ansible/` is the S3 bucket and path respectively.

<dl>
  <dt>`--force`</dt>
  <dd>Overwrite existing artifact.  Otherwise, and by default, 
     the script will fail if the artifact already exists, 
     because artifacts are supposedly immutable.
  </dd>
  <dt>`--public`</dt>
  <dd>Allow public reads of the artifact.  By default, the artifact's ACL is 
    set to `:private` in S3.
  </dd>
</dl>


### Resolve role or artifact dependencies

Given a file `requirements.yml` in your current directory that looks like this:
<pre>
- url: s3://sps-build-deploy/ansible/ansible-demo-tarball-0.0.0.tbz2
  paths:
    - from: inventory
        to: ./
</pre>
An ansible-sdk command:

`ansible-sdk dependencies`

can resolve the specified dependency by downloading the
tarball to a temporary location and then pull each path `from` the source and 
copy it `to` the specified destination, relative to the current working directory.

### Example requirements.yml

<pre>
- url: https://github.com/geerlingguy/ansible-role-jenkins/archive/1.1.2.tar.gz
  paths:
  - from: ansible-role-jenkins-1.1.2/.
    to: roles/jenkins
- url: git@github.com:geerlingguy/ansible-role-java.git
  paths:
  - from: .
    to: roles/geerlingguy.java
- url: s3://sps-build-deploy/ansible/ansible-demo-tarball-0.0.0.tbz2
  paths:
  - from: inventory
    to: ./
</pre>
