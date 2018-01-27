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
init: ->
    
    context.verbose = true
    context.sarAccel = 0.005
    context.sarAccelmax = 0.2
    context.sarCounterUP = 0
    context.sarCounterDOWN = 0
    context.marginFactor = 0.8
    context.invested = false # ToDo: dynamisch ermitteln!

#executed on tick
handle: ->

    instrument =  data.instruments[0]
    currentPrice = instrument.price #current price
    storage.startPrice ?= instrument.price #initial price
    storage.coin ?= instrument.pair.substring(0, 3).toUpperCase() #coin name

    marginInfo = mt.getMarginInfo instrument
    currentBalance = marginInfo.margin_balance #current margin balance
    tradeableBalance = marginInfo.tradable_balance #current tradeable margin balance
    storage.startBalance ?= marginInfo.margin_balance  #initial margin balance

    lastTotalProfitPercent = (currentBalance / storage.startBalance - 1) * 100 #Profit vor aktuellem Trade

    currentPosition = mt.getPosition instrument
    if currentPosition 
        curPosAmount = currentPosition.amount
        curPosPrice = currentPosition.price
        curPosBalanceAtStart = curPosAmount * curPosPrice
        curPosBalance = curPosAmount * currentPrice
        curPosProfit = curPosBalance - curPosBalanceAtStart
        curPosProfitPercent = (curPosBalance / curPosBalanceAtStart - 1) * 100
        curBalanceTotal = currentBalance + curPosProfit
        curProfitPercentTotal = (curBalanceTotal / storage.startBalance - 1) * 100
       
        if context.verbose
            debug "POS AMOUNT________________: #{curPosAmount} #{storage.coin}"
            debug "POS BUY PRICE_____________: #{curPosPrice.toFixed(2)} USD"
            debug "POS BALANCE_______________: #{curPosBalance.toFixed(2)} USD"
            debug "START BALANCE_____________: #{curPosBalanceAtStart.toFixed(2)} USD"
            debug "PROFIT CURRENT TRADE______: #{curPosProfit.toFixed(2)} USD (#{curPosProfitPercent.toFixed(2)}%)"

        info "PROFIT IN TOTAL___________: #{curBalanceTotal.toFixed(2)} USD (#{curProfitPercentTotal.toFixed(2)}%)"

###########################################     Logging     ##############################################

    if context.verbose
        debug "CURRENT BALANCE____: #{currentBalance.toFixed(2)} USD"
        debug "CURRENT PRICE______: #{currentPrice.toFixed(2)} USD"    

    debug "BOT PROFIT w/o CUR TRADE__: #{lastTotalProfitPercent.toFixed(2)}%"
    debug "BUY & HOLD PROFIT_________: #{((currentPrice / storage.startPrice - 1) *  100).toFixed(2)}%"     

###########################################     SAR functions   ###########################################
  
    sar = functions.sar(instrument.high, instrument.low, 1,context.sarAccel, context.sarAccelmax)    

    if (instrument.price >= sar)
        context.sarCounterUP = 0
        context.sarCounterDOWN++
        plotMark
            "sarDOWN": sar
                
    if (instrument.price < sar)
        context.sarCounterDOWN = 0
        context.sarCounterUP++
        plotMark
            "sarUP": sar
        
############################################    Trading   ###############################################

    ########    CLOSING     ########     
    
    if  (context.sarCounterDOWN == 1 || context.sarCounterUP == 1) || (context.longPosition == false && (curPosProfitPercent < -2 || curPosProfitPercent > 2))
        if currentPosition
            debug "Closing position"
            mt.closePosition instrument
            marginInfo = mt.getMarginInfo instrument #update margin info after close
            context.invested = false
            sendSMS "Position closed with #{curPosProfit.toFixed(2)} % Profit"

    ########    LONG     ######## 

    if  context.sarCounterDOWN == 1
        unless context.invested
            try 
                # open long position
                if mt.buy instrument, 'market', (marginInfo.tradable_balance / currentPrice) * context.marginFactor,currentPrice,instrument.interval * 60   #Kaufe mit 80% des tradeable balance, abbruch nach "60(interval bei 1h) x 60 sek"
                    context.invested = true
                    context.longPosition = true
#                   context.sarAccel = 0.005
                    sendEmail "New long position"
            catch e 
                # the exception will be thrown if funds are not enough
                if /insufficient funds/.exec e
                    error "insufficient funds"
                else
                    throw e # it is important to rethrow an unhandled exception

    ########    SHORT     ######## 

    if context.sarCounterUP == 1
        unless context.invested
            try 
                # open short position
                if mt.sell instrument, 'market', (marginInfo.tradable_balance / currentPrice) * context.marginFactor,currentPrice,instrument.interval * 60 
                    context.invested = true
                    context.longPosition = false
 #                  context.sarAccel = 0.005
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
    
    if currentPosition = mt.getPosition instrument
        debug "Closing position"
        mt.closePosition instrument
    
    marginInfo = mt.getMarginInfo instrument
    currentBalance = marginInfo.margin_balance #current margin balance

    debug "Start balance was__: #{storage.startBalance} USD"
    debug "End balance is_____: #{currentBalance} USD"

    warn "Bot Gewinn_________: #{((currentBalance / storage.startBalance - 1)*100).toFixed(2)}%"
    warn "B&H Gewinn_________: #{((instrument.price / storage.startPrice - 1)*100).toFixed(2)}%" 
#   debug "Bot started at #{new Date(storage.botStartedAt)}"
#   debug "Bot stopped at #{new Date(data.at)}"
 