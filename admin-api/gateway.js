'use strict';

const FabricCAServices = require('fabric-ca-client');
const { FileSystemWallet, Gateway, X509WalletMixin } = require('fabric-network');
const util = require('util')
const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');
const walletPath = path.join(process.cwd(), 'wallet');
const wallet = new FileSystemWallet(walletPath);
const gateway = new Gateway();

async function enrollAdmin() {
    try {
        // Check to see if we've already enrolled the admin user.
        const adminExists = await wallet.exists('admin');
        if (adminExists) {
            console.log('An identity for the admin user "admin" already exists in the wallet');
            console.log('Wallet identities: ' + util.inspect(wallet.list()));
            console.log('Wallet admin exists: ' + util.inspect(wallet.exists('admin')));
            return;
        }

        // Create a new CA client for interacting with the CA.
        const caURL = ccp.certificateAuthorities['ca-org1'].url;
        console.log('CA URL: ' + caURL);
        const ca = new FabricCAServices(caURL);

        // Enroll the admin user, and import the new identity into the wallet.
        const enrollment = await ca.enroll({ enrollmentID: ccp.certificateAuthorities['ca-org1'].registrar[0].enrollId, enrollmentSecret: ccp.certificateAuthorities['ca-org1'].registrar[0].enrollSecret });
        const identity = X509WalletMixin.createIdentity('org1MSP', enrollment.certificate, enrollment.key.toBytes());
        console.log(`Wallet path: ${walletPath}`);
        await wallet.import('admin', identity);
        console.log('Successfully enrolled admin user "admin" and imported it into the wallet');
        console.log('Wallet identities: ' + util.inspect(wallet.list()));
        console.log('Wallet admin exists: ' + util.inspect(wallet.exists('admin')));
    } catch (error) {
        console.error(`Failed to enroll admin user "admin": ${error}`);
        process.exit(1);
    }
}
async function adminGateway() {

        let ccp = yaml.safeLoad(fs.readFileSync('connection-profile/connection-profile.yaml', 'utf8'));

        // Set connection options; identity and wallet
        let connectionOptions = {
          identity: 'admin',
          wallet: wallet,
          discovery: { enabled:true }
        };

        // Connect to gateway using application specified parameters
        console.log('Connecting to Fabric gateway.');

        await gateway.connect(ccp, connectionOptions);

}


exports.enrollAdmin = enrollAdmin;
exports.adminGateway = adminGateway;