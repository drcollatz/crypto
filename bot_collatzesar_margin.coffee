##### Copyright Paules
##### Collbot

mt = require 'margin_trading' # import margin trading module 
talib = require 'talib'  # import technical indicators library (https://cryptotrader.org/talib)

class functions
  
###########################################     TA-lib Indicatots   ########################################### 

  @sar: (high, low, lag, accel, accelmax) ->
    results = talib.SAR
      high: high
      low: low
      startIdx: 0
      endIdx: high.length - lag
      optInAcceleration: accel
      optInMaximum: accelmax
    _.last(results) 

#executed at start
init: (context, data) ->

    context.sarLag  = 1
    context.sarAccel = 0.005
    context.sarAccelmax = 0.2
    context.sarCounterUP = 0
    context.sarCounterDOWN = 0
    @context.invested = false

#executed on tick
handle: (context, data)->

    instrument =  data.instruments[0]
    marginInfo = mt.getMarginInfo instrument

    storage.coin ?= data.instruments[0].pair.substring(0, 3).toUpperCase()
    storage.startBalance ?= marginInfo.margin_balance    #inital margin balance
    storage.startPrice ?= instrument.price #inital price
    
    context.currentBalance = marginInfo.margin_balance #current margin balance
    context.tradeableBalance = marginInfo.tradable_balance #current tradeable margin balance
    context.currentPrice = instrument.price #current price
    context.curBotPerformance = ((context.currentBalance / storage.startBalance - 1)*100).toFixed(2)

    currentPosition = mt.getPosition instrument
   
    if currentPosition
        context.currentPosAmount = currentPosition.amount
        context.currentPosPrice = currentPosition.price
       

###########################################     Logging     ##############################################

    debug "Current BALANCE____: #{context.currentBalance.toFixed(2)} USD"
    debug "Current TR BALANCE_: #{context.tradeableBalance.toFixed(2)} USD"
    debug "Current PRICE______: #{context.currentPrice.toFixed(2)} USD"    
    
    debug "Bot Gewinn_________: #{context.curBotPerformance}% (Differenz seit letzem Trade: #{(context.curBotPerformance - context.lastBotPerformance).toFixed(2)}%)"
    debug "B&H Gewinn_________: #{((context.currentPrice / storage.startPrice - 1)*100).toFixed(2)}%"     

###########################################     SAR functions   ###########################################
  
    sar = functions.sar(instrument.high, instrument.low, context.sarLag,context.sarAccel, context.sarAccelmax)    

    if (instrument.price >= sar)
        debug "SAR war #{++context.sarCounterDOWN}x UNTEN"
        context.sarCounterUP = 0
        plotMark
            "sarDOWN": sar

        
    if (instrument.price < sar)
        debug "SAR war #{++context.sarCounterUP}x OBEN"
        context.sarCounterDOWN = 0
        plotMark
            "sarUP": sar
             
 
############################################    Trading   ###############################################
    
    if  context.sarCounterDOWN == 1
        if currentPosition
            debug "Closing position"
            context.lastBotPerformance = ((context.currentBalance / storage.startBalance - 1)*100).toFixed(2)
            mt.closePosition instrument
            @context.invested = false
            marginInfo = mt.getMarginInfo instrument
            context.currentBalance = marginInfo.margin_balance #current margin balance
            context.tradeableBalance = marginInfo.tradable_balance #current tradeable margin balance
            context.currentPrice = instrument.price #current price

    if  context.sarCounterDOWN == 1
        unless @context.invested
            try 
                price = instrument.price
                # open long position
                if mt.buy instrument, 'limit', (marginInfo.tradable_balance / price) * 0.8,price,instrument.interval * 60   #Kaufe mit 80% des tradeable balance, abbruch nach "60(interval bei 1h) x 60 sek"
                    currentPosition = mt.getPosition instrument
                    debug "New position: #{currentPosition.amount}"
                    @context.invested = true
                    amount = Math.abs(currentPosition.amount) 
            catch e 
                # the exception will be thrown if funds are not enough
                if /insufficient funds/.exec e
                    error "insufficient funds"
                else
                    throw e # it is important to rethrow an unhandled exception

    if context.sarCounterUP == 1
        if currentPosition
            debug "Closing position"
            context.lastBotPerformance = ((context.currentBalance / storage.startBalance - 1)*100).toFixed(2)
            mt.closePosition instrument 
            @context.invested = false
            marginInfo = mt.getMarginInfo instrument
            context.currentBalance = marginInfo.margin_balance #current margin balance
            context.tradeableBalance = marginInfo.tradable_balance #current tradeable margin balance
            context.currentPrice = instrument.price #current price

    if context.sarCounterUP == 1
        unless @context.invested
            try 
                price = instrument.price
                # open short position
                if mt.sell instrument, 'limit', (marginInfo.tradable_balance / price) * 0.8,price,instrument.interval * 60 
                    currentPosition = mt.getPosition instrument
                    debug "New position: #{currentPosition.amount}"
                    @context.invested = true
                    amount = Math.abs(currentPosition.amount) 
            catch e 
                # the exception will be thrown if funds are not enough
                if /insufficient funds/.exec e
                    error "insufficient funds"
                else
                    throw e # it is important to rethrow an unhandled exception

    debug " "

############################################    ENDE   ###############################################

onStop: ->
    debug "######## BOT ENDE ########"
    
    instrument = @data.instruments[0]
    pos = mt.getPosition instrument
    if pos
        debug "Closing position"
        mt.closePosition instrument

    debug "Start balance was__: #{storage.startBalance} USD"
    debug "End balance is_____: #{context.currentBalance} USD"

    debug "Bot Gewinn_________: #{((context.currentBalance / storage.startBalance - 1)*100).toFixed(2)}%"
    debug "B&H Gewinn__________: #{((context.currentPrice / storage.startPrice - 1)*100).toFixed(2)}%" 
#    debug "Bot started at #{new Date(storage.botStartedAt)}"
#    debug "Bot stopped at #{new Date(data.at)}"
 