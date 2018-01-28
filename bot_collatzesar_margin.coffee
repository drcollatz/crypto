#### Copyright Paules
#### Collbot

#### ToDos

# - bei 'live' Bots verbose automatisch aktivieren
# - beim start checken ob bereits eine Position offen ist und evtl. invested=true setzen
# - Programmablauf / logging etc neu sortieren
# - First Position Strategie? Warten bis zum nächsten Wechsel, oder direkt loslegen?
# - Fees berechnen (0.2 % von komplettem Kauf- oder Verkaufswert)

# Idee: Ultra Fast Bot 1Min-5Min Ticks... Pro Tag nur wenige aber dafür super safe trades "1% und gut" (bei margin sogar nur 0.4% nötig) -> 30% im Monat.

#### START

mt = require 'margin_trading' # import margin trading module 
talib = require 'talib'  # import technical indicators library (https://cryptotrader.org/talib)

class functions

  @OpenPositionPL: (currentPrice, marginPosition) ->
        pl = ((currentPrice - marginPosition.price)/marginPosition.price) * 100
        if (marginPosition.amount < 0)
            return -pl
        else
            return pl

  @OpenPositionCurrentBalance: (currentPrice, startingBalance, marginPosition) ->
        return (startingBalance + marginPosition.amount * (currentPrice - marginPosition.price))

#### TA-lib Indicatots 

  @sar: (high, low, lag, accel, accelmax) ->
    results = talib.SAR
      high: high
      low: low
      startIdx: 0
      endIdx: high.length - lag
      optInAcceleration: accel
      optInMaximum: accelmax
    _.last(results) 

#### Init
init: ->
    
    context.verbose = true
    context.sarAccel = 0.005
    context.sarAccelmax = 0.5
    context.sarAccelShort = 0.01
    context.sarAccelmaxShort = 0.1
    context.sarCounterUP = 0
    context.sarCounterDOWN = 0
    context.marginFactor = 0.8
    context.invested = false # ToDo: dynamisch ermitteln!
    context.positionStatus = "start"

    setPlotOptions
        close:
            color: 'black'
            secondary: true
            size: 5
        exit:
            color: 'red'
            secondary: true
            size: 5
        performance:
            color: 'green'
            secondary: true
            size: 5
            

#### Tick execution
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

##### Logging

    if context.verbose
        debug "Status: #{context.positionStatus}"
        debug "Invested: #{context.invested}"
        debug "------ MARGIN ------"
        debug "CURRENT BALANCE_: #{currentBalance.toFixed(2)} USD"
        debug "START BALANCE___: #{storage.startBalance.toFixed(2)} USD"
        debug "CURRENT PRICE___: #{currentPrice.toFixed(2)} USD"    

    debug "BOT PROFIT______: #{lastTotalProfitPercent.toFixed(2)}% (w/o current position!)"
    debug "B&H PROFIT______: #{((currentPrice / storage.startPrice - 1) *  100).toFixed(2)}%"  

##### Postition


    currentPosition = mt.getPosition instrument
    if currentPosition
        curPosAmount = currentPosition.amount
        curPosPrice = currentPosition.price
        curPosBalanceAtStart = curPosAmount * curPosPrice
        curPosBalance = curPosAmount * currentPrice
        curPosProfit = curPosBalance - curPosBalanceAtStart
        curPosProfitPercent = @functions.OpenPositionPL(instrument.price, currentPosition)
        curBalanceTotal = currentBalance + curPosProfit - storage.startBalance
        curProfitPercentTotal = ((currentBalance + curPosProfit) / storage.startBalance - 1) * 100

        plot
            performance: curProfitPercentTotal

        if context.verbose
            debug "--------------------"
            if curPosAmount > 0
                info "LONG POSITION_____: #{curPosAmount} #{storage.coin} @ #{curPosPrice.toFixed(2)} USD"
            else     
                warn "SHORT POSITION____: #{curPosAmount} #{storage.coin} @ #{curPosPrice.toFixed(2)} USD"                
            debug "CURRENT BALANCE___: #{curPosBalance.toFixed(2)} USD"
            debug "START BALANCE_____: #{curPosBalanceAtStart.toFixed(2)} USD"
            debug "PROFIT POSITION___: #{curPosProfit.toFixed(2)} USD (#{curPosProfitPercent.toFixed(2)}%)"
            debug "PROFIT TOTAL______: #{curBalanceTotal.toFixed(2)} USD (#{curProfitPercentTotal.toFixed(2)}%)"
            debug "Current Margin Balance: #{@functions.OpenPositionCurrentBalance(instrument.price, storage.startBalance, currentPosition)}"

        if curPosProfitPercent < -5
            closePosition = true
            if context.positionStatus == "long"
                context.positionStatus = "short"
            else
                context.positionStatus = "long"                
            warn "EMERGENCY EXIT!"
            plotMark
                exit: 0

##### state machine
  
    sarLong = functions.sar(instrument.high, instrument.low, 1,context.sarAccel, context.sarAccelmax) 
    sarShort = functions.sar(instrument.high, instrument.low, 1,context.sarAccelShort, context.sarAccelmaxShort)

    switch context.positionStatus
        when "start"
            if (sarLong < instrument.price) #long
                context.positionStatus = "long"
                plotMark
                    "sarDOWN": sarLong
                break
        when "long"
            if (sarLong < instrument.price) #long
                context.positionStatus = "long"
                plotMark
                    "sarDOWN": sarLong
                break
            if (sarLong > instrument.price) #short
                context.positionStatus = "short"
                closePosition = true
                break
        when "short" 
            if (sarShort < instrument.price) #long
                closePosition = true
                context.positionStatus = "wait"
                break
            if (sarShort > instrument.price) #short
                plotMark
                    "sarUP": sarShort   
                break
        when "wait"
            if (sarLong < instrument.price) #long
                context.positionStatus = "long"
                plotMark
                    "sarDOWN": sarLong

#### Trading

######## CLOSING 
    
    if closePosition
        if currentPosition
            warn "Closing position"
            mt.closePosition instrument
            marginInfo = mt.getMarginInfo instrument #update margin info after close
            context.invested = false
            closePosition = false
            if curPosProfit >= 0
                info "Juhuu, du hast eben #{curPosProfit.toFixed(2)} USD (#{curPosProfitPercent.toFixed(2)}%) verdient!"
                sendSMS "Juhuu, du hast eben #{curPosProfit.toFixed(2)} USD (#{curPosProfitPercent.toFixed(2)}%) verdient!"
            else
                warn "Shit, du hast eben #{curPosProfit.toFixed(2)} USD (#{curPosProfitPercent.toFixed(2)}%) verloren"
                sendSMS "Shit, du hast eben #{curPosProfit.toFixed(2)} USD (#{curPosProfitPercent.toFixed(2)}%) verloren"                
            plotMark
                close: 1

######## LONG 

    if  context.positionStatus == "long" 
        unless context.invested
            try 
                # open long position
                if mt.buy instrument, 'market', (marginInfo.tradable_balance / currentPrice) * context.marginFactor,currentPrice,instrument.interval * 60   #Kaufe mit 80% des tradeable balance, abbruch nach "60(interval bei 1h) x 60 sek"
                    info "Fee: #{((((marginInfo.tradable_balance / currentPrice) * context.marginFactor ) * currentPrice) * 0.002).toFixed(2)}"
                    context.invested = true
                    sendEmail "New long position"
            catch e 
                # the exception will be thrown if funds are not enough
                if /insufficient funds/.exec e
                    error "insufficient funds"
                else
                    throw e # it is important to rethrow an unhandled exception

######## SHORT

    if context.positionStatus == "short"
        unless context.invested
            try 
                # open short position
                debug "versuche zu verkaufen..."
                if mt.sell instrument, 'market', (marginInfo.tradable_balance / currentPrice) * context.marginFactor,currentPrice,instrument.interval * 60 
                    context.invested = true
                    sendEmail "New short position"
            catch e 
                # the exception will be thrown if funds are not enough
                if /insufficient funds/.exec e
                    error "insufficient funds"
                else
                    throw e # it is important to rethrow an unhandled exception

    if context.verbose
        debug "######################################################## "

#### ENDE

onStop: ->
    debug "######## BOT ENDE ########"
    
    instrument = @data.instruments[0]
    
    if currentPosition = mt.getPosition instrument
        debug "Closing position"
        mt.closePosition instrument
    
    marginInfo = mt.getMarginInfo instrument
    currentBalance = marginInfo.margin_balance #current margin balance

    debug "Start balance was__: #{storage.startBalance.toFixed(2)} USD"
    debug "End balance is_____: #{currentBalance.toFixed(2)} USD"

    botProfit = ((currentBalance / storage.startBalance - 1)*100)
    buhProfit = ((instrument.price / storage.startPrice - 1)*100)
    if botProfit >= 0
        info "Bot Gewinn_________: #{botProfit.toFixed(2)}%"
    else
        warn "Bot Gewinn_________: #{botProfit.toFixed(2)}%" 
    if buhProfit >= 0
        info "B&H Gewinn_________: #{buhProfit.toFixed(2)}%" 
    else
        warn "B&H Gewinn_________: #{buhProfit.toFixed(2)}%" 
#   debug "Bot started at #{new Date(storage.botStartedAt)}"
#   debug "Bot stopped at #{new Date(data.at)}"       