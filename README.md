ansible-sdk
===========

Ansible Development Kit
=======
# Ansible SDK

## Functions

### Build Role Artifacts

Build an artifact for a role that can be used to distribute the role 
to statisfy requirements thereupon.

This should be executed from the directory containing `roles/`, and will 
build an artifact for each subdirectory in `roles/`. 

### Build Playbook Artifact

Build an artifact for the current directory's playbook and place into 
`build/`.  

This should be executed from the top level playbook directory.

### Publish artifact 

Publish an artifact at a given path to s3.  

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

