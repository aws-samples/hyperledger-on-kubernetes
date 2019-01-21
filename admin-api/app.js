/*
# Copyright 2018 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# 
# Licensed under the Apache License, Version 2.0 (the "License").
# You may not use this file except in compliance with the License.
# A copy of the License is located at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# or in the "license" file accompanying this file. This file is distributed 
# on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either 
# express or implied. See the License for the specific language governing 
# permissions and limitations under the License.
#
*/

'use strict';
//var log4js = require('log4js');
//log4js.configure({
//	appenders: {
//	  out: { type: 'stdout' },
//	},
//	categories: {
//	  default: { appenders: ['out'], level: 'debug' },
//	}
//});
//var logger = log4js.getLogger('FABRICAPI');
const WebSocketServer = require('ws');
var express = require('express');
var bodyParser = require('body-parser');
var http = require('http');
var util = require('util');
var app = express();
var cors = require('cors');
var hfc = require('fabric-client');
const logger = hfc.getLogger('app.js');

const FabricCAServices = require('fabric-ca-client');
const { FileSystemWallet, X509WalletMixin } = require('fabric-network');
const uuidv4 = require('uuid/v4');

var connection = require('./connection.js');
var gateway = require('./gateway.js');
//var query = require('./query.js');
//var invoke = require('./invoke.js');
//var blockListener = require('./blocklistener.js');

hfc.addConfigFile('config.json');
var host = 'localhost';
var port = 3000;
var username = "";
var orgName = "";
var channelName = hfc.getConfigSetting('channelName');
var chaincodeName = hfc.getConfigSetting('chaincodeName');
var peers = hfc.getConfigSetting('peers');
///////////////////////////////////////////////////////////////////////////////
//////////////////////////////// SET CONFIGURATIONS ///////////////////////////
///////////////////////////////////////////////////////////////////////////////
app.options('*', cors());
app.use(cors());
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({
	extended: false
}));
app.use(function(req, res, next) {
	logger.info(' ##### New request for URL %s',req.originalUrl);
	return next();
});

//wrapper to handle errors thrown by async functions. We can catch all
//errors thrown by async functions in a single place, here in this function,
//rather than having a try-catch in every function below. The 'next' statement
//used here will invoke the error handler function - see the end of this script
const awaitHandler = (fn) => {
	return async (req, res, next) => {
		try {
			await fn(req, res, next)
		} 
		catch (err) {
			next(err)
		}
	}
}

///////////////////////////////////////////////////////////////////////////////
//////////////////////////////// START SERVER /////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
var server = http.createServer(app).listen(port, function() {});
logger.info('****************** SERVER STARTED ************************');
logger.info('***************  Listening on: http://%s:%s  ******************',host,port);
server.timeout = 240000;

function getErrorMessage(field) {
	var response = {
		success: false,
		message: field + ' field is missing or Invalid in the request'
	};
	return response;
}

///////////////////////////////////////////////////////////////////////////////
//////////////////////////////// START WEBSOCKET SERVER ///////////////////////
///////////////////////////////////////////////////////////////////////////////
const wss = new WebSocketServer.Server({ server });
wss.on('connection', function connection(ws) {
	logger.info('****************** WEBSOCKET SERVER - received connection ************************');
	ws.on('message', function incoming(message) {
		console.log('##### Websocket Server received message: %s', message);
	});

	ws.send('something');
});

///////////////////////////////////////////////////////////////////////////////
///////////////////////// REST ENDPOINTS START HERE ///////////////////////////
///////////////////////////////////////////////////////////////////////////////
// Health check - can be called by load balancer to check health of REST API
app.get('/health', awaitHandler(async (req, res) => {
	res.sendStatus(200);
}));

// Register and enroll user. A user must be registered and enrolled before any queries 
// or transactions can be invoked
app.post('/users', awaitHandler(async (req, res) => {
	logger.info('================ POST on Users');
	let args = req.body;
	logger.info('##### End point : /users');
	logger.info('##### POST on Users- args : ' + JSON.stringify(args));
	let response = await connection.getRegisteredUser(args, true);
	logger.info('##### POST on Users - returned from registering the username %s for organization %s', args);
    logger.info('##### POST on Users - getRegisteredUser response secret %s', response.secret);
    logger.info('##### POST on Users - getRegisteredUser response message %s', response.message);
    if (response && typeof response !== 'string') {
        logger.info('##### POST on Users - Successfully registered the username %s for organization %s', args);
		logger.info('##### POST on Users - getRegisteredUser response %s', response);
		// Now that we have a username & org, we can start the block listener
		//await blockListener.startBlockListener(channelName, username, orgName, wss);
		res.json(response);
	} else {
		logger.error('##### POST on Users - Failed to register the username %s for organization %s with::%s', args, response);
		res.json({success: false, message: response});
	}
}));

// Enroll an admin user
app.get('/init', awaitHandler(async (req, res) => {
	logger.info('================ GET on Init');
	logger.info('##### End point : /init');
    await gateway.enrollAdmin();
    await gateway.adminGateway();
	logger.info('##### GET on Init - completed');
}));

// Loads the configtx defined for this Fabric network, and prints out the key info such as orgs
app.get('/configtx', awaitHandler(async (req, res) => {
	logger.info('================ GET on loadconfigtx');
	logger.info('##### End point : /loadconfigtx');
    await gateway.loadConfigtx();
	logger.info('##### GET on loadconfigtx - completed');
}));

// Loads the configtx defined for this Fabric network, and prints out the orgs
app.get('/configtx/orgs', awaitHandler(async (req, res) => {
	logger.info('================ GET on endpoint /configtx/orgs');
    let response = await gateway.getOrgsFromConfigtx();
    res.json({success: true, message: response});
	logger.info('##### GET on /configtx/orgs - completed');
}));

// Loads the configtx defined for this Fabric network, and prints out the profiles
app.get('/configtx/profiles', awaitHandler(async (req, res) => {
	logger.info('================ GET on endpoint /configtx/profiles');
    let response = await gateway.getProfilesFromConfigtx();
    res.json({success: true, message: response});
	logger.info('##### GET on /configtx/profiles - completed');
}));

// Add a new org to configtx.yaml and env.sh
app.post('/orgs', awaitHandler(async (req, res) => {
	logger.info('================ POST on orgs');
	let args = req.body;
	logger.info('##### End point : /orgs');
	logger.info('##### POST on orgs - args : ' + JSON.stringify(args));
	let response = await gateway.addOrg(args);
	logger.info('##### POST on orgs - response %s', util.inspect(response));
    if (response && typeof response !== 'string') {
		res.json(response);
	} else {
		logger.error('##### POST on orgs failed: %s', response);
		res.json({success: false, message: response});
	}
}));

// Add a new profile to configtx.yaml
app.post('/configtx/profiles', awaitHandler(async (req, res) => {
	logger.info('================ POST on AddProfile');
	let args = req.body;
	logger.info('##### End point : /addprofile');
	logger.info('##### POST on addprofile - args : ' + JSON.stringify(args));
	let response = await gateway.addConfigtxProfile(args);
	logger.info('##### POST on addprofile - response %s', util.inspect(response));
    if (response && typeof response !== 'string') {
		res.json(response);
	} else {
		logger.error('##### POST on addprofile failed: %s', response);
		res.json({success: false, message: response});
	}
}));

// Generate a new channel transaction config using a profile in configtx.yaml
app.post('/configtx/channelconfigs', awaitHandler(async (req, res) => {
	logger.info('================ POST on configtx/channelconfig');
	let args = req.body;
	logger.info('##### End point : /configtx/channelconfig');
	logger.info('##### POST on configtx/channelconfig - args : ' + JSON.stringify(args));
	let response = await gateway.createTransactionConfig(args);
	logger.info('##### POST on configtx/channelconfig - response %s', util.inspect(response));
    if (response && typeof response !== 'string') {
		res.json(response);
	} else {
		logger.error('##### POST on configtx/channelconfig failed: %s', response);
		res.json({success: false, message: response});
	}
}));

// Generate a new channel transaction config using a profile in configtx.yaml
app.post('/channels', awaitHandler(async (req, res) => {
	logger.info('================ POST on channel');
	let args = req.body;
	logger.info('##### End point : /channel');
	logger.info('##### POST on channel - args : ' + JSON.stringify(args));
	let response = await gateway.createChannel(args);
	logger.info('##### POST on channel - response %s', util.inspect(response));
    if (response && typeof response !== 'string') {
		res.json(response);
	} else {
		logger.error('##### POST on channel failed: %s', response);
		res.json({success: false, message: response});
	}
}));



// Print out the details of the Fabric network
app.get('/networks', awaitHandler(async (req, res) => {
	logger.info('================ GET on networks');
	logger.info('##### End point : /networks');
    await gateway.listNetwork();
	logger.info('##### GET on networks - completed');
}));

//   /networks/org/<orgid>   - add a new org. Adds org to env.sh, gens new directories, gen K8s templates, create K8s namespace, creates PVC
//   /networks/org/<orgid>/register
//  add org to configtx.yaml, using /configtx/org api call
//  create new channel profile and new channel, using configtx/profile and other api calls above


/************************************************************************************
 * Error handler
 ************************************************************************************/

app.use(function(error, req, res, next) {
	res.status(500).json({ error: error.toString() });
});

