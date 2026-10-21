# AppTrust app

## Administration
### Repos
![Project repos](./images/project-repos.png)

#### Virtual repo
##### Docker
![Docker Virtual repo](./images/repo-docker-virtual.png)
##### NPM
![NPM Virtual repo](./images/repo-npm-virtual.png)

### Lifecycle
![Project lifecycle](./images/lifecycle.png)

## Compliance
![Project compliance](./images/project-compliance.png)


## Platform
### Application
![Project app](./images/project-application.png)


## Pipeline: DOCKER 
- Copied ./Dockerfile to ./jfrog/Dockerfile and updated to download image from JFrog
```
#FROM nginx:1.31.6-alpine
# https://hub.docker.com/_/nginx/
FROM psazuse.jfrog.io/npmapptrust-docker-virtual/nginx:1.31.6-alpine
```

## Dev command
```
./jfrog/jfcli.sh
```
