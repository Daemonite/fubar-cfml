<cfcomponent output="false" persistent="false">
	
	<!--- Bot detection --->
	<cfset this.botRegex = "(bot\b|\brss|slurp|mediapartners-google|googlebot|zyborg|emonitor|jeeves|sbider|findlinks|yahooseeker|mmcrawler|jbrowser|java|pmafind|blogbeat|converacrawler|ocelli|labhoo|validator|sproose|ia_archiver|larbin|psycheclone|arachmo" />
	
	<!--- Basic server information --->
	<cfset this.basicInfo = structnew() />
	<cfset this.basicInfo.containertype = iif(IsDefined("server.coldfusion.appserver"),"server.coldfusion.appserver",DE("unkown")) />
	<cfset this.basicInfo.machineName = createObject("java", "java.net.InetAddress").localhost.getHostName() />
	<cfswitch expression="#this.containertype#">
		<cfcase value="jrun4" >
			<cfset this.basicInfo.instance = createObject("java", "jrunx.kernel.JRun").getServerName() />
		</cfcase>
		<cfcase value="j2ee">
			<cfif getEngine() is "coldfusion">
				<!--- Use a try/catch in case CFIDE.adminapi.runtime is restricted or unavailable --->
				<cftry>
					<cfset this.basicInfo.instance = createObject("component", "CFIDE.adminapi.runtime").getInstanceName() />
					<cfcatch>
						<cfset this.basicInfo.instance = getPageContext().getServletContext().getServletContextName() />
					</cfcatch>
				</cftry>
			<cfelse>
				<cfset this.basicInfo.instance = getPageContext().getServletContext().getServletContextName() />
			</cfif>
		</cfcase>
		<cfdefaultcase>
			<cfset this.basicInfo.instance = "unknown" />
		</cfdefaultcase>
	</cfswitch>
	
	<cffunction name="collectRequestInfo" access="public" returntype="struct" output="false" hint="Returns a struct containing information that should be included in every error report">
		<cfset var stResult = duplicate(this.basicInfo) />
		<cfset var headers = GetHttpRequestData().headers />
		
		<cfset stResult["bot"] = refindnocase(this.botRegex,cgi.http_user_agent) />
		<cfset stResult["browser"] = cgi.HTTP_USER_AGENT />
		<cfset stResult["datetime"] = now() />
		<cfset stResult["host"] = cgi.http_host />
		<cfset stResult["httpreferer"] = cgi.http_referer />
		<cfset stResult["scriptname"] = cgi.script_name />
		<cfset stResult["querystring"] = cgi.query_string />
		<cfset stResult["remoteaddress"] = cgi.remote_addr />
		<cfset stResult["host"] = cgi.http_host />
		
		<!--- Add arguments to result --->
		<cfset structappend(stResult,arguments,false) />
		
		<cfif structkeyexists(headers,"X-User-Agent")>
			<cfset stResult["browser"] = headers["X-User-Agent"] />
		</cfif>
		<cfif structkeyexists(headers,"X-Forwarded-For")>
			<cfset stResult["remoteaddress"] = trim(listfirst(headers["X-Forwarded-For"])) />
		</cfif>
		
		<cfreturn stResult />
	</cffunction>
	
	
	<cffunction name="getStack" access="public" returntype="array" output="false" hint="Returns a stack array">
		<cfargument name="bIncludeJava" type="boolean" required="false" default="true" />
		<cfargument name="ignoreLines" type="numeric" required="false" default="0" hint="Number of stack lines to omit from result" />
		
		<cfset var aResult = arraynew(1) />
		<cfset var aStacktrace = createobject("java","java.lang.Throwable").getStackTrace() />
		<cfset var stLine = structnew() />
		<cfset var i = 0 />
		<cfset var found = 0 />
		<cfset var ignored = 0 />
		
		<cfloop from="1" to="#arraylen(aStackTrace)#" index="i">
			<cfset stLine = structnew() />
			<cfset stLine["template"] = aStackTrace[i].getFileName() />
			<cfset stLine["line"] = aStackTrace[i].getLineNumber() />
			
			<cfif structkeyexists(stLine,"template") and refindnocase("\.(cfc|cfm)$",stLine.template)>
				<cfset found = found + 1 />
			</cfif>
			
			<cfif found gt 1>
				<cfif refindnocase("\.java$",stLine.template)>
					<cfset stLine["location"] = "java" />
				<cfelse>
					<cfset stLine["location"] = "cfml" />
				</cfif>
				
				<cfif (arguments.bIncludeJava or stLine["location"] neq "java") and ignored gte arguments.ignoreLines>
					<cfset arrayappend(aResult,stLine) />
				<cfelseif (arguments.bIncludeJava or stLine["location"] neq "java") and ignored lt arguments.ignoreLines>
					<cfset ignored = ignored + 1 />
				</cfif>
			</cfif>
		</cfloop>
		
		<cfreturn aResult />
	</cffunction>
	
	<cffunction name="normalizeError" access="public" returntype="struct" output="false" hint="Simplifies and auguments error struct">
		<cfargument name="exception" type="any" required="true" />
		
		<cfset var stException = structnew() />
		<cfset var stResult = collectRequestInfo() />
		
		<cfset var aStack = arraynew(1) />
		<cfset var stLine = structnew() />
		<cfset var i = 0 />
		
		<cfset stException = arguments.exception />
		
		<cfif structKeyExists(arguments.exception, "rootcause")>
			<cfset structappend(duplicate(arguments.exception),arguments.exception.rootcause,true) />
		</cfif>
		
		<cfset stResult["message"] = stException.message />
		
		<!--- Normalize the stack trace --->
		<cfset stResult["stack"] = arraynew(1) />
		<cfloop from="1" to="#arraylen(stException.TagContext)#" index="i">
			<cfset stLine = structnew() />
			<cfset stLine["template"] = stException.TagContext[i].template />
			<cfset stLine["line"] = stException.TagContext[i].line />
			
			<cfif refindnocase("\.java$",stLine.template)>
				<cfset stLine["location"] = "java" />
			<cfelse>
				<cfset stLine["location"] = "cfml" />
			</cfif>
		</cfloop>
		
		<cfif structKeyExists(stException, "type") and len(stException.type)>
			<cfset stResult["type"] = stException.type />
		</cfif>
		<cfif structKeyExists(stException, "errorcode") and len(stException.errorcode)>
			<cfset stResult["errorcode"] = stException.errorcode />
		</cfif>
		<cfif structKeyExists(stException, "detail") and len(stException.detail)>
			<cfset stResult["detail"] = stException.detail />
		</cfif>
		<cfif structKeyExists(stException, "extended_info") and len(stException.extended_info)>
			<cfset stResult["extended_info"] = stException.extended_info />
		</cfif>
		<cfif structKeyExists(stException, "queryError") and len(stException.queryError)>
			<cfset stResult["queryError"] = stException.queryError />
		</cfif>
		<cfif structKeyExists(stException, "sql") and len(stException.sql)>
			<cfset stResult["sql"] = stException.sql />
		</cfif>
		<cfif structKeyExists(stException, "where") and len(stException.where)>
			<cfset stResult["where"] = stException.where />
		</cfif>
		
		<cfreturn stResult />
	</cffunction>
	
	<cffunction name="create404Error" access="public" returntype="struct" output="false" hint="Constructs a 404 error struct">
		<cfargument name="message" type="string" required="false" default="Page does not exist" />
		
		<cfset var stError = collectRequestInfo() />
		
		<cfset stError["message"] = arguments.message />
		<cfset stError["url"] = duplicate(URL) />
		
		<cfset logToCouch("404",stError) />
		
		<cfreturn stError />
	</cffunction>
	
	
	<cffunction name="formatError" access="public" output="false" returntype="any" hint="Formats normalized error for use in HTML or email">
		<cfargument name="exception" type="struct" required="true" />
		<cfargument name="format" type="string" required="false" default="html" hint="[html | text | json]" />
		
		<cfset var output = createObject("java","java.lang.StringBuffer").init() />
		<cfset var first = true />
		
		<cfswitch expression="#arguments.format#">
			<cfcase value="json">
				<cfreturn serializeJSON(arguments.exception) />
			</cfcase>
			
			<cfcase value="html">
				<cfset output.append("<h2>Error Overview</h2><table>") />
				<cfset output.append("<tr><th>Machine:</th><td>#arguments.exception.machineName#</td></tr>") />
				<cfset output.append("<tr><th>Instance:</th><td>#arguments.exception.instancename#</td></tr>") />
				<cfset output.append("<tr><th>Message:</th><td>#arguments.exception.message#</td></tr>") />
				<cfset output.append("<tr><th>Browser:</th><td>#arguments.exception.browser#</td></tr>") />
				<cfset output.append("<tr><th>DateTime:</th><td>#arguments.exception.datetime#</td></tr>") />
				<cfset output.append("<tr><th>Host:</th><td>#arguments.exception.host#</td></tr>") />
				<cfset output.append("<tr><th>HTTPReferer:</th><td>#arguments.exception.httpreferer#</td></tr>") />
				<cfset output.append("<tr><th>QueryString:</th><td>#arguments.exception.querystring#</td></tr>") />
				<cfset output.append("<tr><th>RemoteAddress:</th><td>#arguments.exception.remoteaddress#</td></tr>") />
				<cfset output.append("<tr><th>Bot:</th><td>#arguments.exception.bot#</td></tr>") />
				<cfset output.append("</table><h2>Error Details</h2><table>") />
				<cfif structKeyExists(arguments.exception, "type") and len(arguments.exception.type)>
					<cfset output.append("<tr><th>Exception Type:</th><td>#arguments.exception.type#</td></tr>") />
				</cfif>
				<cfif structKeyExists(arguments.exception, "detail") and len(arguments.exception.detail)>
					<cfset output.append("<tr><th>Detail:</th><td>#arguments.exception.detail#</td></tr>") />
				</cfif>
				<cfif structKeyExists(arguments.exception, "extended_info") and len(arguments.exception.extended_info)>
					<cfset output.append("<tr><th>Extended Info:</th><td>#arguments.exception.extended_info#</td></tr>") />
				</cfif>
				<cfif structKeyExists(arguments.exception, "queryError") and len(arguments.exception.queryError)>
					<cfset output.append("<tr><th>Error:</th><td>#arguments.exception.queryError#</td></tr>") />
				</cfif>
				<cfif structKeyExists(arguments.exception, "sql") and len(arguments.exception.sql)>
					<cfset output.append("<tr><th>SQL:</th><td>#arguments.exception.sql#</td></tr>") />
				</cfif>
				<cfif structKeyExists(arguments.exception, "where") and len(arguments.exception.where)>
					<cfset output.append("<tr><th>Where:</th><td>#arguments.exception.where#</td></tr>") />
				</cfif>
				
				<cfif structKeyExists(arguments.exception, "stack") and arraylen(arguments.exception.stack)>
					<cfset output.append("<tr><th valign='top'>Tag Context:</th><td><ul>") />
					<cfloop from="1" to="#arrayLen(arguments.exception.stack)#" index="i">
						<cfset output.append("<li>#arguments.exception.stack[i].template# (line: #arguments.exception.stack[i].line#)</li>") />
					</cfloop>
					<cfset output.append("</ul></td></tr>") />
				</cfif>
				
				<cfif structKeyExists(arguments.exception, "url")>
					<cfset output.append("<tr><th valign='top'>Post-process URL:</th><td><ul>") />
					<cfloop list="#listsort(structkeylist(arguments.exception.url),'textnocase')#" index="i">
						<cfset output.append("<li>#i# = #htmleditformat(arguments.exception.url[i])#</li>") />
					</cfloop>
					<cfset output.append("</ul></td></tr>") />
				</cfif>
				
				<cfset output.append("</table>") />
			</cfcase>
			
			<cfcase value="text">
				<cfset output.append(ucase('Error Overview') & variables.newline) />
				<cfset output.append("Machine              : #arguments.exception.machineName#" & variables.newline) />
				<cfset output.append("Instance             : #arguments.exception.instancename#" & variables.newline) />
				<cfset output.append("Message              : #arguments.exception.message#" & variables.newline) />
				<cfset output.append("Browser              : #arguments.exception.browser#" & variables.newline) />
				<cfset output.append("DateTime             : #arguments.exception.datetime#" & variables.newline) />
				<cfset output.append("Host                 : #arguments.exception.host#" & variables.newline) />
				<cfset output.append("HTTPReferer          : #arguments.exception.httpreferer#" & variables.newline) />
				<cfset output.append("QueryString          : #arguments.exception.querystring#" & variables.newline) />
				<cfset output.append("RemoteAddress        : #arguments.exception.remoteaddress#" & variables.newline) />
				<cfset output.append("Bot                  : #arguments.exception.bot#" & variables.newline) />
				<cfset output.append(variables.newline) />
				
				<cfset output.append(ucase('Error Details') & variables.newline) />
				<cfif structKeyExists(arguments.exception, "type") and len(arguments.exception.type)>
					<cfset output.append("Exception Type       : #arguments.exception.type#" & variables.newline) />
				</cfif>
				<cfif structKeyExists(arguments.exception, "detail") and len(arguments.exception.detail)>
					<cfset output.append("Detail               : #arguments.exception.detail#" & variables.newline) />
				</cfif>
				<cfif structKeyExists(arguments.exception, "extended_info") and len(arguments.exception.extended_info)>
					<cfset output.append("Extended Info        : #arguments.exception.extended_info#" & variables.newline) />
				</cfif>
				<cfif structKeyExists(arguments.exception, "queryError") and len(arguments.exception.queryError)>
					<cfset output.append("Error                : #arguments.exception.queryError#" & variables.newline) />
				</cfif>
				<cfif structKeyExists(arguments.exception, "sql") and len(arguments.exception.sql)>
					<cfset output.append("SQL                  : #arguments.exception.sql#" & variables.newline) />
				</cfif>
				<cfif structKeyExists(arguments.exception, "where") and len(arguments.exception.where)>
					<cfset output.append("Where                : #arguments.exception.where#" & variables.newline) />
				</cfif>
				
				<cfif structKeyExists(arguments.exception, "stack") and arraylen(arguments.exception.stack)>
					<cfset output.append("Tag Context          :     ") />
					<cfloop from="1" to="#arrayLen(arguments.exception.stack)#" index="i">
						<cfif i neq 1>
							<cfset output.append("                  ")>
						</cfif>
						
						<cfset output.append("- #arguments.exception.stack[i].template# (line: #arguments.exception.stack[i].line#)" & variables.newline) />
					</cfloop>
				</cfif>
				
				<cfif structKeyExists(arguments.exception, "url")>
					<cfset output.append("Post-process URL    : ") />
					<cfloop list="#listsort(structkeylist(arguments.exception.url),'textnocase')#" index="i">
						<cfif not first>
							<cfset output.append("                 ")>
						</cfif>
						<cfset first = false />
						
						<cfset output.append("#i# = #arguments.exception.url[i]#") />
					</cfloop>
				</cfif>
			</cfcase>
		</cfswitch>
		
		<cfreturn output.toString() />
	</cffunction>
	
	
	<cffunction name="logToCouch" access="public" output="false" returntype="void" hint="Logs data to the couchdb">
		<cfargument name="type" type="string" required="true" hint="Log type" />
		<cfargument name="data" type="struct" requried="true" hint="Log data" />
		
		<cfif isdefined("application.config.cdb.host") and len(application.config.cdb.host) 
			and isdefined("application.config.cdb.port") and len(application.config.cdb.port)
			and isdefined("application.config.cdb.db") and len(application.config.cdb.db)>
			
			<cfset arguments.data = duplicate(arguments.data) />
			
			<cfset arguments.data["logtype"] = arguments.type />
			<cfset arguments.data["application"] = application.applicationname />
			<cfif isdefined("application.sysinfo.version")>
				<cfset arguments.data["farcry"] = application.sysinfo.version />
			</cfif>
			<cfif isdefined("application.sysinfo.engine")>
				<cfset arguments.data["engine"] = application.sysinfo.engine />
			</cfif>
            <cfif isdefined("session.sessionid")>
            	<cfset arguments.data["sessionid"] = session.sessionID />
            </cfif>
			<cfset arguments.data["datetimeorderable"] = dateformat(arguments.data.datetime,"yyyy-mm-dd") & " " & timeformat(arguments.data.datetime,"HH:mm:ss") />
			<cfset arguments.data["datetime"] = dateformat(arguments.data["datetime"],"mmmm, dd yyyy") & " " & timeformat(arguments.data["datetime"],"HH:mm:ss")>
			
			
			<cfhttp url="http://#application.config.cdb.host#/#application.config.cdb.db#" 
					port="#application.config.cdb.port#" 
					method="POST" 
					username="#application.config.cdb.username#" 
					password="#application.config.cdb.password#"
					timeout="0">
				
				<cfhttpparam type="header" name="Content-Type" value="application/json">
				<cfhttpparam type="body" value="#serializeJSON(arguments.data)#">
				
			</cfhttp>
			
		</cfif>
	</cffunction>
	
	<cffunction name="logData" access="public" output="false" returntype="void" hint="Logs error to application and exception log files">
		<cfargument name="log" type="struct" required="true" />
		<cfargument name="bApplication" type="boolean" required="false" default="true" />
		<cfargument name="bException" type="boolean" required="false" default="true" />
		<cfargument name="bCouch" type="boolean" required="false" default="true" />
		
		<cfset var stacktrace = createObject("java","java.lang.StringBuffer").init() />
		<cfset var i = 0 />
		<cfset var firstline = "N/A" />
		<cfset var logtype = "error" />
		
		<cfif structkeyexists(arguments.log,"logtype")>
			<cfset logtype = arguments.log.logtype />
			<cfset structdelete(arguments.log,"logtype") />
		</cfif>
		
		<cfset logToCouch(logtype,arguments.log) />
		
		<cfif structkeyexists(arguments.log,"stack") and arraylen(arguments.log.stack)>
			<cfset firstline = "The specific sequence of files included or processed is #arguments.log.stack[1].template#, line: #arguments.log.stack[1].line#" />
		</cfif>
		
		<cfif arguments.bApplication and structkeyexists(arguments.log,"message")>
			<cflog log="application" application="true" type="error" text="#arguments.log.message#. #firstline#" />
		</cfif>
		<cfif arguments.bException and structkeyexists(arguments.log,"stack") and structkeyexists(arguments.log,"message")>
			<cfloop from="1" to="#arraylen(arguments.log.stack)#" index="i">
				<cfset stacktrace.append(arguments.log.stack[i].template) />
				<cfset stacktrace.append(":") />
				<cfset stacktrace.append(arguments.log.stack[i].line) />
				<cfif i eq arraylen(arguments.log.stack)>
					<cfset stacktrace.append(variables.newline) />
				</cfif>
			</cfloop>
			<cflog file="exception" application="true" type="error" text="#arguments.log.message#. #firstline##newline##stacktrace.toString()#" />
		</cfif>	
	</cffunction>
	
</cfcomponent>