//  Copyright (c) 2025, WSO2 LLC. (http://www.wso2.org).
//
//  WSO2 LLC. licenses this file to you under the Apache License,
//  Version 2.0 (the "License"); you may not use this file except
//  in compliance with the License.
//  You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing,
//  software distributed under the License is distributed on an
//  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
//  KIND, either express or implied. See the License for the
//  specific language governing permissions and limitations
//  under the License.

import ballerina/io;
import ballerina/lang.runtime;
import ballerina/sql;
import ballerinax/aws.redshiftdata;

configurable string accessKeyId = ?;
configurable string secretAccessKey = ?;
configurable redshiftdata:Cluster dbAccessConfig = ?;

public function main() returns error? {
    io:println("Setting up the Music Store database...");
    // Create a Redshift client
    redshiftdata:Client redshift = check new ({
        region: redshiftdata:US_EAST_2,
        auth: {
            accessKeyId,
            secretAccessKey
        },
        dbAccessConfig
    });

    // Creates `albums` table
    sql:ParameterizedQuery createTableQuery = `CREATE TABLE Albums (
        id VARCHAR(100) NOT NULL PRIMARY KEY,
        title VARCHAR(100),
        artist VARCHAR(100),
        price REAL
    );`;
    redshiftdata:ExecutionResponse createTableResponse = check redshift->execute(createTableQuery);
    _ = check waitForCompletion(redshift, createTableResponse.statementId);

    // Adds the records to the `albums` table
    sql:ParameterizedQuery[] insertQueries = [
        `INSERT INTO Albums VALUES('A-123', 'Lemonade', 'Beyonce', 18.98);`,
        `INSERT INTO Albums VALUES('A-321', 'Renaissance', 'Beyonce', 24.98);`
    ];
    redshiftdata:ExecutionResponse insertDescription = check redshift->batchExecute(insertQueries);
    _ = check waitForCompletion(redshift, insertDescription.statementId);
    io:println("Music Store database setup completed successfully.");
}

isolated function waitForCompletion(redshiftdata:Client redshift, string statementId)
returns redshiftdata:DescriptionResponse|redshiftdata:Error {
    foreach int retryCount in 0 ... 9 {
        redshiftdata:DescriptionResponse descriptionResponse = check redshift->describe(statementId);
        if descriptionResponse.status is redshiftdata:FINISHED {
            return descriptionResponse;
        }
        if descriptionResponse.status is redshiftdata:FAILED|redshiftdata:ABORTED {
            return error("Execution did not finish successfully. Status: " + descriptionResponse.status);
        }
        runtime:sleep(1);
    }
    return error("Statement execution did not finish within the expected time");
}
