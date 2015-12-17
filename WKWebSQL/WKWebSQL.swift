//
//  WKWebSQL.swift
//
/*

The MIT License (MIT)
Copyright (c) 2015 Aaron Whiteway (at Metaworks Inc)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/
import Foundation
import UIKit
import SwiftyJSON
import XWebView
import SQLite

/*

I've removed the async operations from this thread. This was causing the thread manager to get overwhelmed and slowed down the plugin

*/

public final class WKWebSQL : NSObject {
    
    static var webView: WKWebView?
    static var database: Dictionary<String, Connection>?
    static let namespace: String = "wkwebsql"
    
    // The functions used to load in WKWebSQL
    public static func LoadPlugin(wv: WKWebView) {
        WKWebSQL.webView = wv
        WKWebSQL.webView!.loadPlugin(WKWebSQL(), namespace: WKWebSQL.namespace)
        
        
        
        let bundle = NSBundle(forClass: WKWebSQL.self)
        guard let path = bundle.pathForResource("WKWebSQL", ofType: "js"),
            let source = try? NSString(contentsOfFile: path, encoding: NSUTF8StringEncoding) else {
                preconditionFailure("FATAL: Internal error")
        }
        let script = WKUserScript(source: source as String, injectionTime: WKUserScriptInjectionTime.AtDocumentStart, forMainFrameOnly: false)
        
        self.webView?.configuration.userContentController.addUserScript(script)
        
    }
    
    
    public override init() {
        if(WKWebSQL.database == nil) {
            WKWebSQL.database = Dictionary<String, Connection>()
        }
    }
    
    // Begin the plugin
    public var CallBackHandler: String = "WKCallBackHandler.CallBack"
    
    /*
    WKWebSQL Interfacing Methods
    -- These methods are used to interact with the JavaScript
    */
    
    public func clearConnections() {
        WKWebSQL.database = nil;
    }
    
    
    // This is required because results.error.debugDescription gives Optional() around the text. And all 4 attempts I made to unwrap it resulted in inner text that is different from desired.
    func ManualUnwrapText(str: String) -> String {
        return str.substringWithRange(Range<String.Index>(start: str.startIndex.advancedBy(9), end: str.endIndex.advancedBy(-1)))
    }
    
    // made to be as close to the executeSQL function of WebSQL
    public func execute(DatabaseName: AnyObject?, TransactionObject: AnyObject?, SQLObject: AnyObject?, ParamsObject: AnyObject?, CallBackID: AnyObject?) {
        let databaseName = (DatabaseName as? String)! + "-T" + (TransactionObject as? String)!
        if(WKWebSQL.database == nil || WKWebSQL.database![databaseName] == nil) {
            syncOpenDatabase((DatabaseName as? String)!, TransactionObject: (TransactionObject as? String)!)
        }
        let connection: Connection = WKWebSQL.database![databaseName]!
        
        let SQL = SQLObject as? String
        let ParamsString = ParamsObject as? String
        let CallBackIDString = CallBackID as? String
        //print(CallBackIDString)
        //print(SQL)
        dispatch_async(dispatch_get_main_queue()) {
            
            var resultsJSON: NSString = ""
            
            do {
                let command = self.getBaseSQLCommand(SQL!)
                let results = connection.prepare(SQL!)
                if(results.error != nil) {
                    
                    self.doCallBack(CallBackIDString, Success: false, Results: "'" + self.ManualUnwrapText(results.error.debugDescription) + "'")
                    
                    return;
                }
                if (ParamsString != nil && ParamsString != "" && ParamsString != "\"\"") {
                    
                    let dataFromString = ParamsString!.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)
                    let Params = JSON(data: dataFromString!)
                    var P_Array = [Binding?]()
                    for (_,subJson):(String, JSON) in Params {
                        P_Array.append(subJson.stringValue as Binding)
                    }
                    let rows = try results.run(P_Array)
                    
                    
                    if(command == "SELECT") {
                        resultsJSON = self.buildJSONFromResults(rows)
                    } else {
                        resultsJSON = self.nonQueryJSONResults(rows, db: connection)
                    }
                    
                    // Need to encode rows
                } else {
                    if(command == "SELECT") {
                        // In this case we need to get the column names and place them into the json array, otherwise it will just be indicies
                        
                        resultsJSON = self.buildJSONFromResults(results)
                        
                    } else {
                        let rows = try results.run()
                        resultsJSON = self.nonQueryJSONResults(rows, db: connection)
                    }
                }
                _ = "JSON.parse('\(resultsJSON as String)')"
                //let ResultsParsing = resultsJSON as String
                self.doCallBack(CallBackIDString, Success: true, Results: resultsJSON as String)
            } catch let exception {
                self.doCallBack(CallBackIDString, Success: false, Results: "'" + (exception as! String) + "'")
            }
        }
    }
    
    
    // Made to be as close to the openDatabase command of WebSQL as possible.
    public func openDatabase(DatabaseName: AnyObject?, Version: AnyObject?) {
        
        
        let databaseName = (DatabaseName as? String)! + "_" + (Version as? String)!
        
        
        //dispatch_async(dispatch_get_main_queue()) {
        // Check to see about putting it elsewhere and flag it
        let dbLocation = NSHomeDirectory() + "/Library/Caches/\(databaseName).sqlite3"
        
        if WKWebSQL.database == nil
        {
            WKWebSQL.database = [String : Connection]()
        }
        if(WKWebSQL.database![databaseName] != nil) {
            return;
        }
        //WKWebSQL.database![databaseName] = try! Connection(dbLocation)
        //}
        _ = try! Connection(dbLocation)
        let url = NSURL(fileURLWithPath: dbLocation)
        do{
        try url.setResourceValue(true, forKey: NSURLIsExcludedFromBackupKey)
        }
        catch {
            print("Failed to remove from backup")
        }        
        
    }
    
    func closeConnection(DatabaseName: AnyObject?, TransactionObject: AnyObject?) {
        let databaseName = (DatabaseName as? String)! + "-T" + (TransactionObject as? String)!
        if(WKWebSQL.database == nil || WKWebSQL.database![databaseName] == nil) {
            return;
        }
        WKWebSQL.database![databaseName] = nil
    }
    
    /*
    Supporting Functions
    -- These functions act to aid in the plugin but are not to be used by it.
    */
    
    // Function to handling calling back to the JavaScript
    func doCallBack(ID: String?, Success: Bool, var Results: String!) {
        if(ID == nil || ID == "") {
            return;
        }
        if(Results == "") {
            Results = "\"\""
        }
        
        
        let Status: String = Success == true ? "Success" : "Failure"
        let JSHandler = self.CallBackHandler + "(" + ID! + ",'\(Status)', \(Results))"
        
        
        /*
        There is potential for good speed up here. Each call to evaluateJavaScript
        creates a new instance of a JSContext which is bound to a virutal machine
        which is then referred back to the JSVM of the webview. This initialization
        for evaluating the javascript was takes up 60-80% of the call time in my test.
        
        Also even with a completionHandler of nil there are call backs (to the native)
        fired so you don't save as much as you'd suspect from using a nil callback.
        These are sent even if the Javascript call you are doing returns nothing.
        */
        //print(Results)
        WKWebSQL.webView!.evaluateJavaScript(JSHandler, completionHandler: nil)
    }
    
    // Safety measure for opening databases, this will be depreciated
    func syncOpenDatabase(DatabaseName: AnyObject?, TransactionObject: AnyObject?) {
        let dbLocation = NSHomeDirectory() + "/Library/Caches/\(DatabaseName as? String).sqlite3"
        if WKWebSQL.database == nil
        {
            WKWebSQL.database = [String : Connection]()
        }
        if(WKWebSQL.database![(DatabaseName as? String)! + "-T" + (TransactionObject as? String)!] != nil) {
            return;
        }
        WKWebSQL.database![(DatabaseName as? String)! + "-T" + (TransactionObject as? String)!] = try! Connection(dbLocation)
        
    }
    
    
    // Method to get column names in for the JSON building
    func getColumnNames(SQL: String) -> [String]? {
        var Columns: [String] = [String]()
        let StringWords = SQL.componentsSeparatedByString(" ")
        var Words:[String] = [String]()
        for w in StringWords {
            for ww in w.componentsSeparatedByString(",") {
                Words.append(ww)
            }
        }
        if Words[0].uppercaseString != "SELECT" {
            return nil
        }
        Words = Words.filter() { $0 != "" }
        var i: Int = 1
        repeat {
            
            var word = Words[i++]
            if(Words[i].uppercaseString == "AS") {
                word = Words[i+1]
                i = i+2;
            }
            word = word.componentsSeparatedByString(".").last! as String
            word = word.stringByReplacingOccurrencesOfString("'", withString: "")
            word = word.stringByReplacingOccurrencesOfString("\"", withString: "")
            Columns.append(word)
        } while Words[i].uppercaseString != "FROM"
        
        return Columns
    }
    
    // Simple method to grab the command type
    func getBaseSQLCommand(SQL: String) -> String {
        return SQL.componentsSeparatedByString(" ").first!.uppercaseString as String
    }
    
    // Take the results of a SELECT query and get the results
    // I can't use a dictionary because not all returns will be strings...
    func buildJSONFromResults(stmt: Statement) -> String {
        let colNames = stmt.columnNames
        var Rows: [String] = [String]()
        for row in stmt {
            var Row: [String] = [String]()
            var i: Int = 0
            for col in row {
                let rPrefix = "\"" + colNames[i++] + "\":"
                if((col as? String) == nil) {
                    Row.append(rPrefix + self.getColAsString(col))
                } else {
                    var dataString = (col as? String)!
                    dataString = dataString.stringByReplacingOccurrencesOfString("\n\r", withString: "\\n")
                    dataString = dataString.stringByReplacingOccurrencesOfString("\r\n", withString: "\\n")
                    dataString = dataString.stringByReplacingOccurrencesOfString("\n", withString: "\\n")
                    dataString = dataString.stringByReplacingOccurrencesOfString("\r", withString: "\\n")
                    dataString = dataString.stringByReplacingOccurrencesOfString("\"", withString: "\\\"")
                    Row.append(rPrefix + "\"" + dataString + "\"")
                }
            }
            Rows.append("{ " + Row.joinWithSeparator(",") + " } ")
        }
        let joinedRows = Rows.joinWithSeparator(",")
        return "{ \"insertId\": null, \"rowsAffceted\": null, \"rows\": [ " + joinedRows + " ] }"
    }
    
    func nonQueryJSONResults(stmt: Statement, db: Connection) -> String {
        let lastInsert = db.lastInsertRowid != nil ? String(db.lastInsertRowid!) : "null"
        let affected = String(db.changes)
        
        return ("{ \"insertId\": \( lastInsert ), \"rowsAffceted\": \(affected), \"rows\": null }") as String
        
    }
    
    // To deal with formatting the column value for JSON
    // Date formatting may be an issue here
    func getColAsString(c: Binding?) -> String {
        if(c is Int64) {
            return String((c as? Int64)!)
        }
        if(c is Double) {
            return String((c as? Double)!)
        }
        // If it is not a number than put it in quotes
        return "\"" + String(c) + "\""
    }
}
