/*
 
 The MIT License (MIT)
 Copyright (c) 2015 Aaron Whiteway (at Metaworks Inc)
 
 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 
 */

// This statement drops any connections that are still open in the native wrapper each time this page is loaded new.
wkwebsql.clearConnections();
var WKWebSQL = {
    
    // Each transaction requires its own instance to work in, this counter tells the native wrapper which instance the commands belong to
TCounter: 0,
RecycledTransactionIDs: [],
    
GenerateTransactionID: function() {
    return TCounter++;
    if(WKWebSQL.RecycledTransactionIDs.length == 0) {
        return TCounter++;
    }
    return WKWebSQL.RecycledTransactionIDs.pop();
},
    
    // This create
openDatabase: function(name, version) {
    wkwebsql.openDatabase(name, version); // This is added to set no back up flag
    return {
    name: name,
    version: version,
        
    transaction: function(func) {
        var TX = WKWebSQL._transaction();
        TX.name = this.name;
        TX.version = this.version;
        TX._open();
        func(TX);
        TX._close();
    },
        
        // This is removed because of the WebSQL specs
        /*
         executeSql: function(SQL, Params, ResultsCallBack, ErrorCallBack) {
         var callBackID = WKCallBackHandler.GenerateCallBackID();
         WKCallBackHandler.AddCallBacks(callBackID, ResultsCallBack, ErrorCallBack);
         wkwebsql.execute(this.name, "", SQL, JSON.stringify(Params), callBackID.toString());
         }
         */
    }
},
    
    
_transaction: function() {
    return {
    name: "",
    version: "",
    transactionID: WKWebSQL.TCounter++,
    _open: function() {
        wkwebsql.execute(this.name, this.transactionID.toString(), "BEGIN DEFERRED TRANSACTION", "", "");
    },
    _close: function() {
        wkwebsql.execute(this.name, this.transactionID.toString(), "COMMIT TRANSACTION", "", "");
        wkwebsql.closeConnection(this.name, this.transactionID.toString());
        //WKWebSQL.RecycledTransactionIDs.push(this.transactionID);
    },
    executeSql: function(SQL, Params, ResultsCallBack, ErrorCallBack) {
        var callBackID = WKCallBackHandler.GenerateCallBackID();
        WKCallBackHandler.AddCallBacks(callBackID, ResultsCallBack, ErrorCallBack);
        WKCallBackHandler.AssociateTransaction(callBackID, this);
        //console.log(this.transactionID);
        //console.log(callBackID);
        //console.log(SQL);
        wkwebsql.execute(this.name, this.transactionID.toString(), SQL, JSON.stringify(Params), callBackID.toString());
    }
    }
}
    
};

window.openDatabase = WKWebSQL.openDatabase;

var WKCallBackHandler = {
CallBackCounter: 0,
SuccessCallBacks: [],
ErrorCallBacks: [],
Transaction: [],
RecycledCallBackIDs: [],
    
GenerateCallBackID: function() {
    return WKCallBackHandler.CallBackCounter++;
    if(WKCallBackHandler.RecycledCallBackIDs.length == 0) {
        WKCallBackHandler.SuccessCallBacks.push(null);
        WKCallBackHandler.ErrorCallBacks.push(null);
        WKCallBackHandler.Transaction.push(null);
        //console.log(WKCallBackHandler.CallBackCounter);
        return WKCallBackHandler.CallBackCounter++;
    } else {
        return WKCallBackHandler.RecycledCallBackIDs.pop();
    }
},
    
RecycleCallBackID: function(ID) {
    WKCallBackHandler.RecycledCallBackIDs.push(ID);
},
    
AddCallBacks: function(ID, SucessCallBack, ErrorCallBack) {
    WKCallBackHandler.SuccessCallBacks[ID] = SucessCallBack;
    WKCallBackHandler.ErrorCallBacks[ID] = ErrorCallBack;
},
AssociateTransaction: function(ID, Trans) {
    WKCallBackHandler.Transaction[ID] = Trans;
},
    
CallBack: function(ID, Result, Results) {
    //console.log(Results);
    //Results = JSON.parse(Results);
    //console.log(ID);
    if(WKCallBackHandler.Transaction[ID] != null)  {
        if (Result == "Success") {
            WKCallBackHandler.SuccessCallBacks[ID](WKCallBackHandler.Transaction[ID], this.SQLResultSet(Results));
        } else {
            WKCallBackHandler.ErrorCallBacks[ID](WKCallBackHandler.Transaction[ID], { "message": Results });
        }
    } else {
        if (Result == "Success") {
            WKCallBackHandler.SuccessCallBacks[ID](this.SQLResultSet(Results));
        } else {
            WKCallBackHandler.ErrorCallBacks[ID]({ "message": Results });
        }
    }
    
    WKCallBackHandler.SuccessCallBacks[ID] = null;
    WKCallBackHandler.ErrorCallBacks[ID] = null;
    WKCallBackHandler.Transaction[ID] = null;
    //WKCallBackHandler.RecycleCallBackID(ID);
    //console.log("Call Back Sucessful :: " + Result)
},
    
SQLResultSet: function(Results) {
    return {
    insertId: Results.insertId,
    rowsAffected: Results.rowsAffected,
    rows: {
    length: Results.rows? Results.rows.length : 0,
    rows: Results.rows,
    item: function(i) {
        if(this.rows && this.rows.length > i) {
            return this.rows[i];
        }
        return null;
    }
    }
    }
}
};