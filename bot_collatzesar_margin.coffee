##### Copyright Paules
##### Collbot

###### ToDos ######

# - bei 'live' Bots verbose automatisch aktivieren
# - beim start checken ob bereits eine Position offen ist und evtl. invested=true setzen
# - Programmablauf / logging etc neu sortieren

# Idee: Ultra Fast Bot 1Min-5Min Ticks... Pro Tag nur wenige aber dafür super safe trades "1% und gut" (bei margin sogar nur 0.4% nötig) -> 30% im Monat.

###################

mt = require 'margin_trading' # import margin trading module 
talib = require 'talib'  # import technical indicators library (https://cryptotrader.org/talib)

class functions
  
###########################################     TA-lib Indicatots   ########################################### 

  @sar: (high, low, lag, accel, accelmax, start) ->
    results = talib.SAR
      high: high
      low: low
      startIdx: start
      endIdx: high.length - lag
      optInAcceleration: accel
      optInMaximum: accelmax
    _.last(results) 

#executed at start
init: (context, data) ->
    
    context.verbose = false
    context.sarLag  = 1
    context.sarAccel = 0.005
    context.sarAccelmax = 0.2
    context.sarStart = 0    
    context.sarCounterUP = 0
    context.sarCounterDOWN = 0
    context.marginFactor = 0.8
    context.curPositionOnLastTrade
    context.curPostiionBalance
    @context.invested = false

#executed on tick
handle: (context, data)->

    instrument =  data.instruments[0]
    marginInfo = mt.getMarginInfo instrument
    currentPosition = mt.getPosition instrument

    storage.coin ?= data.instruments[0].pair.substring(0, 3).toUpperCase()
    storage.startBalance ?= marginInfo.margin_balance  #initial margin balance
    storage.startPrice ?= instrument.price #initial price
    
    context.currentBalance = marginInfo.margin_balance #current margin balance
    context.tradeableBalance = marginInfo.tradable_balance #current tradeable margin balance
    context.currentPrice = instrument.price #current price

    context.curBotPerformanceOnBalance = ((context.currentBalance / storage.startBalance - 1)*100)

    if currentPosition
        context.curPosAmount = currentPosition.amount
        context.curPosPrice = currentPosition.price
        context.curPosStartBalance = currentPosition.amount * currentPosition.price
        context.curPosBalance = currentPosition.amount * context.currentPrice
        context.curPosProfit = (context.curPosBalance - context.curPosStartBalance)
        context.curSumBalance = context.currentBalance + context.curPosProfit
        context.curPLProc = ((context.curSumBalance / storage.startBalance - 1)*100)
        if context.verbose
            debug "POS AMOUNT__________: #{currentPosition.amount} #{storage.coin}"
            debug "POS BUY PRICE_______: #{currentPosition.price.toFixed(2)} USD"
            debug "POS BALANCE_________: #{context.curPosBalance.toFixed(2)} USD"
            debug "START BALANCE_______: #{context.curPosStartBalance.toFixed(2)} USD"
            debug "BOT PROFIT ON TRADE_: #{context.curPosProfit.toFixed(2)} USD"        
            debug "BOT PROFIT IN SUM___: #{context.curSumBalance.toFixed(2)} USD"
            
        info "BOT Gewinn_________: #{context.curPLProc.toFixed(2)} %"
    


###########################################     Logging     ##############################################

    if context.verbose
        info "Current BALANCE____: #{context.currentBalance.toFixed(2)} USD"
        info "Current TR BALANCE_: #{context.tradeableBalance.toFixed(2)} USD"
        info "Current PRICE______: #{context.currentPrice.toFixed(2)} USD"    
    
        warn "Bot Gewinn_________: #{context.curBotPerformanceOnBalance.toFixed(2)}% (Differenz seit letzem Trade: #{(context.curBotPerformanceOnBalance - context.lastBotPerformance).toFixed(2)}%)"
    warn "B&H Gewinn_________: #{((context.currentPrice / storage.startPrice - 1)*100).toFixed(2)} %"     

###########################################     SAR functions   ###########################################
  
    sar = functions.sar(instrument.high, instrument.low, context.sarLag,context.sarAccel, context.sarAccelmax, context.sarStart)    

    if (instrument.price >= sar)
        context.sarCounterUP = 0
        context.sarCounterDOWN++
        plotMark
            "sarDOWN": sar
        if context.verbose
            debug "SAR war #{context.sarCounterDOWN}x UNTEN"
        
    if (instrument.price < sar)
        context.sarCounterDOWN = 0
        context.sarCounterUP++
        plotMark
            "sarUP": sar
        if context.verbose
            debug "SAR war #{context.sarCounterUP}x OBEN"             
 
############################################    Trading   ###############################################

    ########    CLOSING     ########     
    
    if  context.sarCounterDOWN == 1 || context.sarCounterUP == 1
        if currentPosition
            debug "Closing position"
            context.lastBotPerformance = ((context.currentBalance / storage.startBalance - 1)*100).toFixed(2)
            mt.closePosition instrument
            @context.invested = false
            marginInfo = mt.getMarginInfo instrument
            context.currentBalance = marginInfo.margin_balance #current margin balance
            context.tradeableBalance = marginInfo.tradable_balance #current tradeable margin balance
            context.currentPrice = instrument.price #current price
            sendSMS "Position closed"

    ########    LONG     ######## 

    if  context.sarCounterDOWN == 1
        unless @context.invested
            try 
                price = instrument.price
                # open long position
                if mt.buy instrument, 'limit', (marginInfo.tradable_balance / price) * context.marginFactor,price,instrument.interval * 60   #Kaufe mit 80% des tradeable balance, abbruch nach "60(interval bei 1h) x 60 sek"
                    currentPosition = mt.getPosition instrument
                    @context.invested = true
                    amount = Math.abs(currentPosition.amount)
                    context.curPositionOnLastTrade = currentPosition.amount * context.currentPrice 
#                    context.sarAccel = 0.005
                    sendEmail "New long position"
            catch e 
                # the exception will be thrown if funds are not enough
                if /insufficient funds/.exec e
                    error "insufficient funds"
                else
                    throw e # it is important to rethrow an unhandled exception

    ########    SHORT     ######## 

    if context.sarCounterUP == 1
        unless @context.invested
            try 
                price = instrument.price
                # open short position
                if mt.sell instrument, 'limit', (marginInfo.tradable_balance / price) * context.marginFactor,price,instrument.interval * 60 
                    currentPosition = mt.getPosition instrument
                    @context.invested = true
                    amount = Math.abs(currentPosition.amount)
                    context.curPositionOnLastTrade = currentPosition.amount * context.currentPrice
 #                   context.sarAccel = 0.005
                    sendEmail "New short position"
            catch e 
                # the exception will be thrown if funds are not enough
                if /insufficient funds/.exec e
                    error "insufficient funds"
                else
                    throw e # it is important to rethrow an unhandled exception

    if context.verbose
        debug " "

############################################    ENDE   ###############################################

onStop: ->
    debug "######## BOT ENDE ########"
    
    instrument = @data.instruments[0]
    pos = mt.getPosition instrument
    if pos
        debug "Closing position"
        mt.closePosition instrument
    
    marginInfo = mt.getMarginInfo instrument
    context.currentBalance = marginInfo.margin_balance #current margin balance
    context.currentPrice = instrument.price #current price

    debug "Start balance was__: #{storage.startBalance} USD"
    debug "End balance is_____: #{context.currentBalance} USD"

    debug "Bot Gewinn_________: #{((context.currentBalance / storage.startBalance - 1)*100).toFixed(2)}%"
    debug "B&H Gewinn__________: #{((context.currentPrice / storage.startPrice - 1)*100).toFixed(2)}%" 
#    debug "Bot started at #{new Date(storage.botStartedAt)}"
#    debug "Bot stopped at #{new Date(data.at)}"
 