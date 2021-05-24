FROM node:10

COPY node_modules /opt/node_modules

COPY src /opt/src
COPY bin /opt/bin
COPY package.json /opt/package.json

EXPOSE 3000

WORKDIR /opt

ENTRYPOINT ["npm", "start"]