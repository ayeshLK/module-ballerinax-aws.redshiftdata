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

import ballerina/sql;
import ballerina/test;

type User record {|
    @sql:Column {name: "user_id"}
    int userId;
    string username;
    string email;
    int age;
|};

type UserWithoutEmailField record {|
    @sql:Column {name: "user_id"}
    int userId;
    string username;
    int age;
|};

type UserOpenRecord record {
};

type SupportedTypes record {|
    @sql:Column {name: "int_type"}
    int intType;
    @sql:Column {name: "bigint_type"}
    int bigintType;
    @sql:Column {name: "double_type"}
    float doubleType;
    @sql:Column {name: "boolean_type"}
    boolean booleanType;
    @sql:Column {name: "string_type"}
    string stringType;
    @sql:Column {name: "nil_type"}
    () nilType;
|};

@test:Config {
    groups: ["getResultAsStream"]
}
isolated function testBasicQueryResult() returns error? {
    User[] expectedUsers = [
        {userId: 1, username: "JohnDoe", email: "john.doe@example.com", age: 25},
        {userId: 2, username: "JaneSmith", email: "jane.smith@example.com", age: 30},
        {userId: 3, username: "BobJohnson", email: "bob.johnson@example.com", age: 22}
    ];

    sql:ParameterizedQuery query = `SELECT * FROM Users;`;
    ExecutionResponse res = check redshiftData->execute(query);
    DescriptionResponse descriptionResponse = check waitForCompletion(redshiftData, res.statementId);
    test:assertEquals(descriptionResponse.status, FINISHED);
    stream<User, Error?> resultStream = check redshiftData->getResultAsStream(res.statementId);
    User[] resultArray = check from User user in resultStream
        select user;

    test:assertEquals(resultArray.length(), 3);
    test:assertEquals(resultArray[0], expectedUsers[0]);
    test:assertEquals(resultArray[1], expectedUsers[1]);
    test:assertEquals(resultArray[2], expectedUsers[2]);
}

@test:Config {
    groups: ["getResultAsStream"]
}
isolated function testParameterizedQueryResult() returns error? {
    int userId = 1;
    sql:ParameterizedQuery query = `SELECT * FROM Users WHERE user_id = ${userId};`;
    ExecutionResponse res = check redshiftData->execute(query);
    DescriptionResponse descriptionResponse = check waitForCompletion(redshiftData, res.statementId);
    test:assertEquals(descriptionResponse.status, FINISHED);
    stream<User, Error?> resultStream = check redshiftData->getResultAsStream(res.statementId);
    User[] resultArray = check from User user in resultStream
        select user;

    test:assertEquals(resultArray.length(), 1);
    test:assertEquals(resultArray[0].username, "JohnDoe");
}

@test:Config {
    groups: ["getResultAsStream"]
}
isolated function testSupportedTypes() returns error? {
    SupportedTypes data = {
        intType: 12,
        bigintType: 9223372036854774807,
        doubleType: 123.34,
        booleanType: true,
        stringType: "test",
        nilType: ()
    };

    sql:ParameterizedQuery insertQuery = `INSERT INTO SupportedTypes (
        int_type, bigint_type, double_type, boolean_type, string_type, nil_type) VALUES 
        (${data.intType}, ${data.bigintType}, ${data.doubleType}, ${data.booleanType},
         ${data.stringType},  ${data.nilType}
        );`;
    ExecutionResponse insertStmResponse = check redshiftData->execute(insertQuery);
    DescriptionResponse insertStmResult = check waitForCompletion(redshiftData, insertStmResponse.statementId);
    test:assertEquals(insertStmResult.status, FINISHED);

    sql:ParameterizedQuery selectQuery = `SELECT * FROM SupportedTypes;`;
    ExecutionResponse selectQueryResponse = check redshiftData->execute(selectQuery);
    DescriptionResponse selectQueryResult = check waitForCompletion(redshiftData, selectQueryResponse.statementId);
    test:assertEquals(selectQueryResult.status, FINISHED);
    stream<SupportedTypes, Error?> queryResult = check redshiftData->getResultAsStream(selectQueryResponse.statementId);

    SupportedTypes[] resultArray = check from SupportedTypes item in queryResult
        select item;

    test:assertEquals(resultArray.length(), 1);
    test:assertEquals(resultArray[0], data);
}

@test:Config {
    groups: ["getResultAsStream"]
}
isolated function testNoQueryResult() returns error? {
    sql:ParameterizedQuery query = `DROP TABLE IF EXISTS non_existent_table;`;
    ExecutionResponse res = check redshiftData->execute(query);
    DescriptionResponse descriptionResponse = check waitForCompletion(redshiftData, res.statementId);
    test:assertEquals(descriptionResponse.status, FINISHED);
    stream<User, Error?>|Error queryResult = redshiftData->getResultAsStream(res.statementId);
    test:assertTrue(queryResult is Error);
    if queryResult is Error {
        ErrorDetails errorDetails = queryResult.detail();
        test:assertEquals(errorDetails.httpStatusCode, 400);
        test:assertEquals(errorDetails.errorMessage, "Query does not have result. Please check query status with " +
                "DescribeStatement.");
    }
}

@test:Config {
    groups: ["getResultAsStream"]
}
isolated function testNoResultRows() returns error? {
    sql:ParameterizedQuery query = `SELECT * FROM Users WHERE user_id = 0;`;
    ExecutionResponse res = check redshiftData->execute(query);
    DescriptionResponse descriptionResponse = check waitForCompletion(redshiftData, res.statementId);
    test:assertEquals(descriptionResponse.status, FINISHED);
    stream<User, Error?> resultStream = check redshiftData->getResultAsStream(res.statementId);
    User[] resultArray = check from User user in resultStream
        select user;

    test:assertEquals(resultArray.length(), 0);
}

@test:Config {
    groups: ["getResultAsStream"]
}
isolated function testInvalidStatementId() returns error? {
    StatementId invalidStatementId = "InvalidStatementId";
    stream<User, Error?>|Error queryResult = redshiftData->getResultAsStream(invalidStatementId);
    test:assertTrue(queryResult is Error);
    if queryResult is Error {
        ErrorDetails errorDetails = queryResult.detail();
        test:assertEquals(errorDetails.httpStatusCode, 400);
        string errorMessage = errorDetails.errorMessage ?: "";
        test:assertTrue(errorMessage.startsWith("id must satisfy regex pattern:"));
    }
}

@test:Config {
    groups: ["getResultAsStream"]
}
isolated function testIncorrectStatementId() returns error? {
    stream<User, Error?>|Error queryResult = redshiftData->getResultAsStream("70662acc-f334-46f8-b953-3a9546796d7k");
    test:assertTrue(queryResult is Error);
    if queryResult is Error {
        ErrorDetails errorDetails = queryResult.detail();
        test:assertEquals(errorDetails.httpStatusCode, 400);
        test:assertEquals(errorDetails.errorMessage, "Query does not exist.");
    }
}

@test:Config {
    groups: ["getResultAsStream"]
}
isolated function testMissingFieldInUserType() returns error? {
    sql:ParameterizedQuery query = `SELECT * FROM Users;`;
    ExecutionResponse res = check redshiftData->execute(query);
    DescriptionResponse descriptionResponse = check waitForCompletion(redshiftData, res.statementId);
    test:assertEquals(descriptionResponse.status, FINISHED);
    stream<UserWithoutEmailField, Error?>|Error resultStream = redshiftData->getResultAsStream(res.statementId);
    test:assertTrue(resultStream is Error);
    if resultStream is Error {
        test:assertEquals(resultStream.message(), "Error occurred while executing the getResultAsStream: " +
                "Error occurred while creating the Record Stream: Field 'email' not found in the record type.");
    }
}

@test:Config {
    groups: ["getResultAsStream"]
}
isolated function testUserWithOpenRecord() returns error? {
    sql:ParameterizedQuery query = `SELECT * FROM Users;`;
    ExecutionResponse res = check redshiftData->execute(query);
    DescriptionResponse descriptionResponse = check waitForCompletion(redshiftData, res.statementId);
    test:assertEquals(descriptionResponse.status, FINISHED);
    stream<UserOpenRecord, Error?> resultStream = check redshiftData->getResultAsStream(res.statementId);
    UserOpenRecord[] resultArray = check from UserOpenRecord user in resultStream
        select user;
    test:assertEquals(resultArray[0],
            {"user_id": 1, "email": "john.doe@example.com", "age": 25, "username": "JohnDoe"});
}

@test:Config {
    groups: ["queryResult"]
}
isolated function testResultPagination() returns error? {
    sql:ParameterizedQuery query = `SELECT 
        a.n + b.n * 10 + c.n * 100 + d.n * 1000 AS num,
        REPEAT('X', 100000) AS large_column -- Generates a string of 10000 'X's
        FROM 
            (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) a,
            (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) b,
            (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) c,
            (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d
        WHERE 
        a.n + b.n * 10 + c.n * 100 + d.n * 1000 <= 1600;
        `;
    ExecutionResponse res = check redshiftData->execute(query);
    DescriptionResponse descriptionResponse = check waitForCompletion(redshiftData, res.statementId);
    test:assertEquals(descriptionResponse.status, FINISHED);

    int resultSize = descriptionResponse.resultSize / 1024 / 1024; // Convert bytes to MB
    int totalRows = descriptionResponse.resultRows;
    test:assertTrue(resultSize >= 150);

    stream<record {int num;}, Error?> resultStream = check redshiftData->getResultAsStream(res.statementId);
    record {int num;}[] resultArray = check from var item in resultStream
        select item;

    test:assertEquals(resultArray.length(), totalRows);
}
