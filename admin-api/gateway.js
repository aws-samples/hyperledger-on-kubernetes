'use strict';

const FabricCAServices = require('fabric-ca-client');
const Client = require('fabric-client');
const logger = Client.getLogger('gw');
const { FileSystemWallet, Gateway, X509WalletMixin } = require('fabric-network');
const util = require('util')
const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');
const walletPath = path.join(process.cwd(), 'wallet');
const wallet = new FileSystemWallet(walletPath);
const gateway = new Gateway();
let configtx = '';

async function enrollAdmin() {
    try {
        // Check to see if we've already enrolled the admin user.
        const adminExists = await wallet.exists('admin');
        if (adminExists) {
            logger.info('An identity for the admin user "admin" already exists in the wallet');
            logger.info('Wallet identities: ' + util.inspect(wallet.list()));
            logger.info('Wallet admin exists: ' + util.inspect(wallet.exists('admin')));
            return;
        }

        // Create a new CA client for interacting with the CA.
        const caURL = ccp.certificateAuthorities['ca-org1'].url;
        logger.info('CA URL: ' + caURL);
        const ca = new FabricCAServices(caURL);

        // Enroll the admin user, and import the new identity into the wallet.
        const enrollment = await ca.enroll({ enrollmentID: ccp.certificateAuthorities['ca-org1'].registrar[0].enrollId, enrollmentSecret: ccp.certificateAuthorities['ca-org1'].registrar[0].enrollSecret });
        const identity = X509WalletMixin.createIdentity('org1MSP', enrollment.certificate, enrollment.key.toBytes());
        logger.info(`Wallet path: ${walletPath}`);
        await wallet.import('admin', identity);
        logger.info('Successfully enrolled admin user "admin" and imported it into the wallet');
        logger.info('Wallet identities: ' + util.inspect(wallet.list()));
        logger.info('Wallet admin exists: ' + util.inspect(wallet.exists('admin')));
    } catch (error) {
        logger.error(`Failed to enroll admin user "admin": ${error}`);
    }
}
async function adminGateway() {

        let ccp = yaml.safeLoad(fs.readFileSync('connection-profile/connection-profile.yaml', 'utf8'));

        // Set connection options; identity and wallet
        let connectionOptions = {
          identity: 'admin',
          wallet: wallet,
          discovery: { enabled:true, asLocalhost:false }
        };

        // Connect to gateway using application specified parameters
        logger.info('Connecting to Fabric gateway.');

        await gateway.connect(ccp, connectionOptions);

}

async function listNetwork() {

    logger.info('Printing out the Fabric network');
    let client = gateway.getClient();
    logger.info('Client: ' + util.inspect(client));
    logger.info('ClientConfig: ' + util.inspect(client.getClientConfig()));
    let msp = client.getMspid();
    logger.info('msp: ' + util.inspect(msp));
    let peers = client.getPeersForOrg();
    logger.info('peers: ' + util.inspect(peers));

}


async function loadConfigtx(configtxPath) {

    try {
        logger.info('Loading the Fabric configtx.yaml at path: ' + configtxPath);
        configtx = yaml.safeLoad(fs.readFileSync(configtxPath, 'utf8'));
        logger.info('Configtx loaded: ' + util.inspect(configtx));
    } catch (error) {
        logger.error('Failed to loadConfigtx: ' + error);
    }

}

async function saveConfigtx(configtxPath) {

    try {
        logger.info('Saving the Fabric configtx.yaml at path: ' + configtxPath);
        logger.info('Backing up original configtx.yaml at path: ' + configtxPath);
        fs.copyFileSync(configtxPath, configtxPath + Math.floor(Date.now() / 1000));
        fs.writeFile(configtxPath, yaml.safeDump(configtx), function(err) {
                if (err) throw err;
            });
        logger.info('Configtx saved: ' + util.inspect(configtx));
    } catch (error) {
        logger.error('Failed to saveConfigtx: ' + error);
    }

}

async function addOrg(configtxPath, org) {

    try {
        logger.info('Reading the Fabric configtx.yaml at path: ' + configtxPath);
        await loadConfigtx(configtxPath);
        //Copy an existing org
        let neworg = JSON.parse(JSON.stringify(configtx['Organizations'][0]));
        let orgname = neworg['Name'];
        let mspdir = neworg['MSPDir'];
        console.log("Neworg: " + util.inspect(neworg));
        neworg['Name'] = org;
        neworg['ID'] = org + 'MSP';
        neworg['MSPDir'] = mspdir.replace(orgname, org);
        neworg['Policies']['Readers']['Rule'] = neworg['Policies']['Readers']['Rule'].replace(orgname, org);
        neworg['Policies']['Writers']['Rule'] = neworg['Policies']['Writers']['Rule'].replace(orgname, org);
        neworg['Policies']['Admins']['Rule'] = neworg['Policies']['Admins']['Rule'].replace(orgname, org);
        console.log("Neworg: " + util.inspect(neworg));
        configtx['Organizations'].push(neworg);
        logger.info('Configtx updated with org: ' + util.inspect(configtx));
    } catch (error) {
        logger.error('Failed to addOrg: ' + error);
    }

}

async function getOrgs(configtxPath) {

    try {
        logger.info('Reading the Fabric configtx.yaml at path: ' + configtxPath);
        await loadConfigtx(configtxPath);
        for (let org in configtx['Organizations']) {
            console.log("Orgs: " + util.inspect(org));
            console.log("Orgs in this network are: " + configtx['Organizations'][org]['Name'] + ' with MSP ' + configtx['Organizations'][org]['ID']);
        }
    } catch (error) {
        logger.error('Failed to getOrgs: ' + error);
    }

}

exports.enrollAdmin = enrollAdmin;
exports.adminGateway = adminGateway;
exports.listNetwork = listNetwork;
exports.loadConfigtx = loadConfigtx;
exports.saveConfigtx = saveConfigtx;
exports.addOrg = addOrg;
exports.getOrgs = getOrgs;