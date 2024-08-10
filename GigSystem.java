import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.sql.Types;
import java.sql.CallableStatement;
import java.sql.Time;

import java.io.IOException;
import java.util.Properties;

import java.time.LocalDateTime;
import java.sql.Timestamp;
import java.util.Vector;
import java.util.Arrays;
import java.util.ArrayList;
import java.util.List;

public class GigSystem {

    public static void main(String[] args) {

        // You should only need to fetch the connection details once
        // You might need to change this to either getSocketConnection() or getPortConnection() - see below
        Connection conn = getSocketConnection();

        boolean repeatMenu = true;
        
        while(repeatMenu){
            System.out.println("_________________________");
            System.out.println("________GigSystem________");
            System.out.println("_________________________");

            System.out.println("1: Find the line up for a given gigID");
            System.out.println("4: An act cancels a gig");
            System.out.println("q: Quit");

            String menuChoice = readEntry("Please choose an option: ");

            if(menuChoice.length() == 0){
                //Nothing was typed (user just pressed enter) so start the loop again
                continue;
            }
            char option = menuChoice.charAt(0);

            /**
             * If you are going to implement a menu, you must read input before you call the actual methods
             * Do not read input from any of the actual task methods
             */
            switch(option){
                case '1':
                    int gigChoice = Integer.parseInt(readEntry("Enter the ID of the gig you want to see the line up for: "));
                    String[][] gigArr = task1(conn, gigChoice);
                    printTable(gigArr);
                    break;

                case '2':
                    break;
                case '3':
                    break;
                case '4':
                    break;
                case '5':
                    break;
                case '6':
                    break;
                case '7':
                    break;
                case '8':
                    break;
                case 'q':
                    repeatMenu = false;
                    break;
                default: 
                    System.out.println("Invalid option");
            }
        }
    }

    /*
     * You should not change the names, input parameters or return types of any of the predefined methods in GigSystem.java
     * You may add extra methods if you wish (and you may overload the existing methods - as long as the original version is implemented)
     */

    /*The Java program needs to be able to find the line-up for any given gigID. 
    There should be the actname, the time they will start and the time they will finish. 
    The task1 method must return this information in the twodimensional array of 
    strings as shown here.*/
    public static String[][] task1(Connection conn, int gigID){
        String[][] gig_info;
        ArrayList<String[]> temp = new ArrayList<>();
        String query = "SELECT a.actname, aft.ontime, aft.finish_time FROM act_finish_time aft JOIN act a ON aft.actID = a.actID JOIN gig g ON aft.gigID = g.gigID WHERE g.gigID = ? ";
        PreparedStatement getGigInfo;
        try{
            conn.setAutoCommit(false);
            getGigInfo = conn.prepareStatement(query);
            getGigInfo.setInt(1,gigID);
            ResultSet gigRs = getGigInfo.executeQuery();

            conn.commit();
            return convertResultToStrings(gigRs);
        }
        catch(SQLException e){
            try{
                conn.rollback();
            } catch (SQLException e2){
                e2.printStackTrace();
            }
            e.printStackTrace();
            } finally{
                try{
                    if(conn != null){
                        conn.setAutoCommit(true);
                    }
                } catch(SQLException e) {
                    e.printStackTrace();
                }
            }
    return null;
    }

    /*Task 2: Organising a Gig
    Set up a new gig at a given venue (referred to as a string containing the venue name).
    There will be an array of ActPerformanceDetails objects which gives details of the actID, the fee, the the
    datetime the act will start, and the duration of the act. There will be a standard adult ticket price provided
    (adultTicketPrice).
    If any details of the gig (or acts) violate any of the constraints described in the specification, ensure the
    database state is as it was before the method was called.*/
    public static void task2(Connection conn, String venue, String gigTitle, LocalDateTime gigStart, int adultTicketPrice, ActPerformanceDetails[] actDetails){
        int venueID = 0;
        int gigID = 0;
        String ticket_type = "A";
        Timestamp gigStartTime = Timestamp.valueOf(gigStart);

        PreparedStatement act_gigIN;
        PreparedStatement set_gig;
        PreparedStatement get_gigID;
        PreparedStatement gig_ticket_IN;
        
        try{
            conn.setAutoCommit(false);

            
        //Insert new gig into gig table
            String gig_in = "INSERT INTO gig(venueID, gigtitle, gigdatetime, gigstatus)" + 
            "VALUES((SELECT venueID FROM venue WHERE venuename = ?), ?, ?, ?) RETURNING gigID";
            
            set_gig = conn.prepareStatement(gig_in, Statement.RETURN_GENERATED_KEYS);
            set_gig.setString(1,venue);
            set_gig.setString(2,gigTitle);
            set_gig.setTimestamp(3,gigStartTime);
            set_gig.setString(4, "GoingAhead");
            set_gig.executeUpdate();

            //Retrieve the generated gigID
            try (ResultSet generatedKeys = set_gig.getGeneratedKeys()) {
                if (generatedKeys.next()) {
                    gigID = generatedKeys.getInt(1);
                }
                else {
                    throw new SQLException("Creating gig failed, no ID obtained.");
                }
            }

            String act_gig_insert = "INSERT INTO act_gig(actID, gigID, actgigfee, ontime, duration)" +
             "VALUES(?, ?, ?, ?, ?)"; 
            act_gigIN = conn.prepareStatement(act_gig_insert);
            // Inserting the performances into the act_gig table
            for (int i = 0; i < actDetails.length; i++) {
                Timestamp ontime = Timestamp.valueOf(actDetails[i].getOnTime());
                act_gigIN.setInt(1, actDetails[i].getActID()); 
                act_gigIN.setInt(2, gigID);
                act_gigIN.setInt(3, actDetails[i].getFee());
                act_gigIN.setTimestamp(4, ontime);
                act_gigIN.setInt(5, actDetails[i].getDuration());
                act_gigIN.addBatch();
            }
            act_gigIN.executeBatch();
            act_gigIN.close();  
            

            //Inserting the tickets into the gig_ticket table
            String gig_ticket_insert = "INSERT INTO gig_ticket(gigID, pricetype, price) VALUES(?, ?, ?)";
            PreparedStatement gig_ticketIN = conn.prepareStatement(gig_ticket_insert);
            gig_ticketIN.setInt(1, gigID);
            gig_ticketIN.setString(2, ticket_type);
            gig_ticketIN.setInt(3, adultTicketPrice);
            gig_ticketIN.executeUpdate();
            gig_ticketIN.close();
            
            //Commit the transaction
            conn.commit();
        } catch(SQLException e){
            try{
                conn.rollback();
            } catch (SQLException e2){
                e2.printStackTrace();
            }
            e.printStackTrace();
            } finally{
                try{
                    if(conn != null){
                        conn.setAutoCommit(true);
                    }
                } catch(SQLException e) {
                    e.printStackTrace();
                }
            }

    }
        
    
    /*A customer wants to buy a ticket. You will be provided with a gigID, a customer name, email and a ticketType
    (which may match a pricetype from gig_ticket). If any details are inconsistent (e.g. if the gig does not exist,
    or there is no matching pricetype, or there is some other error), do not allow the ticket purchase and ensure
    the database state is as it was before the method was called.
    */
   //Looks like I'm dealing with the ticket, gigticket and gig tables
public static void task3(Connection conn, int gigid, String name, String email, String ticketType) {
    CallableStatement bookTicketStmt = null;

    try {
        conn.setAutoCommit(false);

        // Prepare and execute the stored procedure using CALL
        String callProcedure = "CALL book_ticket(?, ?, ?, ?)";
        bookTicketStmt = conn.prepareCall(callProcedure);
        bookTicketStmt.setInt(1, gigid);
        bookTicketStmt.setString(2, name);
        bookTicketStmt.setString(3, email);
        bookTicketStmt.setString(4, ticketType);
        bookTicketStmt.execute();

        conn.commit();
    } catch (SQLException e) {
        System.err.println("SQL Error: " + e.getMessage());
        try {
            if (conn != null) conn.rollback();
        } catch (SQLException ex) {
            System.err.println("SQL Error during rollback: " + ex.getMessage());
        }
    } finally {
        try {
            if (bookTicketStmt != null) bookTicketStmt.close();
            if (conn != null) conn.setAutoCommit(true);
        } catch (SQLException ex) {
            System.err.println("SQL Error: " + ex.getMessage());
        }
    }
}




public static String[][] task4(Connection conn, int gigID, String actName) {
    CallableStatement cancelActStmt = null;
    CallableStatement cancelGigStmt = null;
    ResultSet results = null;
    List<String[]> resultList = new ArrayList<>();
    List<String> emailList = new ArrayList<>();


    try {
        conn.setAutoCommit(false);

        //We set the cursor to be able to move back to the start, as we will be checking for both cases where just an act is cancelled or a whole gig is cancelled in one go
        cancelActStmt = conn.prepareCall("SELECT * FROM cancel_act_in_gig((SELECT actID from act WHERE actname = ?), ?)",
                ResultSet.TYPE_SCROLL_INSENSITIVE, ResultSet.CONCUR_READ_ONLY);
        cancelActStmt.setString(1, actName);
        cancelActStmt.setInt(2, gigID);
        results = cancelActStmt.executeQuery();
        String[][] resultOut;

        boolean isCustomerEmail = false;
        while (results.next()) {
            if (results.getString("customeremail") != null) {
                isCustomerEmail = true;
                emailList.add(results.getString("customeremail"));
            }
        }

        // Reset the cursor of the result set
        results.beforeFirst();

        if (isCustomerEmail) {
            // Process and return customer emails
            resultOut = new String[][] { emailList.toArray(new String[0]) };
            System.out.println(Arrays.deepToString(resultOut));
            return resultOut;
        } else {
            // Process act information
            while (results.next()) {
                String actname = results.getString("actname");
                Time ontime = results.getTime("ontime");
                Time finishTime = results.getTime("finish_time");
                resultList.add(new String[]{actname, ontime != null ? ontime.toString() : null, finishTime != null ? finishTime.toString() : null});
            }
        }

        conn.commit();
    } catch (SQLException e) {
        System.err.println("SQL Error: " + e.getMessage());
        try {
            conn.rollback();
        } catch (SQLException ex) {
            System.err.println("Error during rollback: " + ex.getMessage());
        }

        // Call cancel_gig function if a business rule is violated
        try {
            cancelGigStmt = conn.prepareCall("SELECT * FROM cancel_gig(?)");
            cancelGigStmt.setInt(1, gigID);
            results = cancelGigStmt.executeQuery();

            while (results.next()) {
                resultList.add(new String[]{results.getString("customeremail")});
            }
            conn.commit();
        } catch (SQLException ex) {
            System.err.println("SQL Error during cancel_gig: " + ex.getMessage());
            try {
                conn.rollback();
            } catch (SQLException ex2) {
                System.err.println("Error during rollback: " + ex2.getMessage());
            }
        } finally {
            if (cancelGigStmt != null) {
                try {
                    cancelGigStmt.close();
                } catch (SQLException ex) {
                    System.err.println("Error closing cancelGigStmt: " + ex.getMessage());
                }
            }
            if (results != null) {
                try {
                    results.close();
                } catch (SQLException ex) {
                    System.err.println("Error closing results: " + ex.getMessage());
                }
            }
        }
    } finally {
        try {
            if (conn != null) {
                conn.setAutoCommit(true);
            }
            if (cancelActStmt != null) {
                cancelActStmt.close();
            }
            if (results != null) {
                results.close();
            }
        } catch (SQLException ex) {
            System.err.println("SQL Error during cleanup: " + ex.getMessage());
        }
    }

    return resultList.toArray(new String[0][]);
}


//Task 5
public static String[][] task5(Connection conn){
    try (PreparedStatement ticketsStmt = conn.prepareStatement("SELECT * FROM get_tickets_to_sell()")) {
        conn.setAutoCommit(false);
        ResultSet ticketsToBreakEven = ticketsStmt.executeQuery();
        conn.commit();
        return convertResultToStrings(ticketsToBreakEven);
    } catch (SQLException e) {
        try {
            if (conn != null) conn.rollback();
        } catch (SQLException ex) {
            System.err.println("Rollback error: " + ex.getMessage());
        }
        System.err.println("SQL error: " + e.getMessage());
    } finally {
        try {
            if (conn != null) conn.setAutoCommit(true);
        } catch (SQLException ex) {
            System.err.println("Auto-commit error: " + ex.getMessage());
        }
    }
    return new String[0][0];
}

public static String[][] task6(Connection conn) {
    String[][] result = null;

    try (CallableStatement gigsInYear = conn.prepareCall("SELECT * FROM calculate_headline_act_ticket_sales()")) {
        conn.setAutoCommit(false);

        try (ResultSet gigsInYearResult = gigsInYear.executeQuery()) {
            result = convertResultToStrings(gigsInYearResult);
            conn.commit();
        } catch (SQLException e) {
            conn.rollback();
            throw new RuntimeException("Error executing task 6: " + e.getMessage(), e);
        } finally {
            conn.setAutoCommit(true);
        }
    } catch (SQLException e) {
        System.err.println("SQL Error: " + e.getMessage());
    }

    return result;
}

    public static String[][] task7(Connection conn){
        try(CallableStatement regCustomers = conn.prepareCall("SELECT act_name, customer_name FROM regular_customers()")){
            conn.setAutoCommit(false);

            try (ResultSet regCustomersResult = regCustomers.executeQuery()) {
                return convertResultToStrings(regCustomersResult);
            } catch (SQLException e) {
                conn.rollback();
                throw new RuntimeException("Error executing task 7: " + e.getMessage(), e);
            } finally {
                conn.setAutoCommit(true);
            }
        }
        catch (SQLException e) {
            System.err.println("SQL Error: " + e.getMessage());
        }
        return new String[0][0];
    }

    public static String[][] task8(Connection conn){
        try(CallableStatement economicGigs = conn.prepareCall("SELECT * FROM feasible_gigs()")){
            conn.setAutoCommit(false);

            try (ResultSet economicGigsResult = economicGigs.executeQuery()) {
                return convertResultToStrings(economicGigsResult);
            } catch (SQLException e) {
                conn.rollback();
                throw new RuntimeException("Error executing task 8: " + e.getMessage(), e);
            } finally {
                conn.setAutoCommit(true);
            }
        }
        catch (SQLException e) {
            System.err.println("SQL Error: " + e.getMessage());
        }
        return new String[0][0];
    }

    /**
     * Prompts the user for input
     * @param prompt Prompt for user input
     * @return the text the user typed
     */

    private static String readEntry(String prompt) {
        
        try {
            StringBuffer buffer = new StringBuffer();
            System.out.print(prompt);
            System.out.flush();
            int c = System.in.read();
            while(c != '\n' && c != -1) {
                buffer.append((char)c);
                c = System.in.read();
            }
            return buffer.toString().trim();
        } catch (IOException e) {
            return "";
        }

    }
     
    /**
    * Gets the connection to the database using the Postgres driver, connecting via unix sockets
    * @return A JDBC Connection object
    */
    public static Connection getSocketConnection(){
        Properties props = new Properties();
        props.setProperty("socketFactory", "org.newsclub.net.unix.AFUNIXSocketFactory$FactoryArg");
        props.setProperty("socketFactoryArg",System.getenv("HOME") + "/cs258-postgres/postgres/tmp/.s.PGSQL.5432");
        Connection conn;
        try{
          conn = DriverManager.getConnection("jdbc:postgresql://localhost/cwk", props);
          return conn;
        }catch(Exception e){
            e.printStackTrace();
        }
        return null;
    }

    /**
     * Gets the connection to the database using the Postgres driver, connecting via TCP/IP port
     * @return A JDBC Connection object
     */
    public static Connection getPortConnection() {
        
        String user = "postgres";
        String passwrd = "password";
        Connection conn;

        try {
            Class.forName("org.postgresql.Driver");
        } catch (ClassNotFoundException x) {
            System.out.println("Driver could not be loaded");
        }

        try {
            conn = DriverManager.getConnection("jdbc:postgresql://127.0.0.1:5432/cwk?user="+ user +"&password=" + passwrd);
            return conn;
        } catch(SQLException e) {
            System.err.format("SQL State: %s\n%s\n", e.getSQLState(), e.getMessage());
            e.printStackTrace();
            System.out.println("Error retrieving connection");
            return null;
        }
    }

    public static String[][] convertResultToStrings(ResultSet rs){
        Vector<String[]> output = null;
        String[][] out = null;
        try {
            int columns = rs.getMetaData().getColumnCount();
            output = new Vector<String[]>();
            int rows = 0;
            while(rs.next()){
                String[] thisRow = new String[columns];
                for(int i = 0; i < columns; i++){
                    thisRow[i] = rs.getString(i+1);
                }
                output.add(thisRow);
                rows++;
            }
            // System.out.println(rows + " rows and " + columns + " columns");
            out = new String[rows][columns];
            for(int i = 0; i < rows; i++){
                out[i] = output.get(i);
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return out;
    }

    public static void printTable(String[][] out){
        int numCols = out[0].length;
        int w = 20;
        int widths[] = new int[numCols];
        for(int i = 0; i < numCols; i++){
            widths[i] = w;
        }
        printTable(out,widths);
    }

    public static void printTable(String[][] out, int[] widths){
        for(int i = 0; i < out.length; i++){
            for(int j = 0; j < out[i].length; j++){
                System.out.format("%"+widths[j]+"s",out[i][j]);
                if(j < out[i].length - 1){
                    System.out.print(",");
                }
            }
            System.out.println();
        }
    }

}