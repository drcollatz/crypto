##### Copyright Paules
##### Collbot

talib = require 'talib'
trading = require "trading"
#params = require "params" #needed for additional parameters

_maximumExchangeFee = .25# params.add "Maximum exchange fee %", .25
_maximumOrderAmount = 1 #params.add "Maximum order amount", 1
_orderTimeout = 30 #params.add "Order timeout", 30


class functions
  
########################################### TA-lib Indicatots ############################################################################################################################ 

  @sar: (high, low, lag, accel, accelmax) ->
    results = talib.SAR
      high: high
      low: low
      startIdx: 0.2
      endIdx: high.length - lag
      optInAcceleration: accel
      optInMaximum: accelmax
    _.last(results) 

#######Extended SAR#########
#  
#  @sarext: (high,low,lag,StartValue, OffsetOnReverse, AccelerationInitLong,AccelerationLong,AccelerationMaxLong,AccelerationInitShort, AccelerationShort, AccelerationMaxShort) ->
#    results = talib.SAREXT
#      high: high
#      low: low
#      startIdx: 0
#      endIdx: high.length - lag
#      optInStartValue: StartValue
#      optInOffsetOnReverse: OffsetOnReverse
#      optInAccelerationInitLong: AccelerationInitLong
#      optInAccelerationLong: AccelerationLong
#      optInAccelerationMaxLong: AccelerationMaxLong
#      optInAccelerationInitShort: AccelerationInitShort
#      optInAccelerationShort: AccelerationShort
#      optInAccelerationMaxShort: AccelerationMaxShort
#    _.last(results)   
#
######################################################################################################################################################################################### 


init: (context, data) ->

    context.sarLag  = 1
    context.sarAccel = 0.02
    context.sarAccelmax = 0.2
    context.sarCounterUP = 1
    context.sarCounterDOWN = 1


handle: (context, data)->

    instrument =  data.instruments[0]
    
    storage.coin ?= data.instruments[0].pair.substring(0, 3).toUpperCase()

    assetsAvailable = @portfolios[instrument.market].positions[instrument.asset()].amount
    context.assetsAvailable = assetsAvailable #current assets
    storage.startAssets ?= assetsAvailable    #inital assets

    currencyAvailable = @portfolios[instrument.market].positions[instrument.curr()].amount
    context.currencyAvailable = currencyAvailable #current currency
    storage.startCurrency ?= currencyAvailable    #inital currency

    context.currentPrice = instrument.price
    storage.startPrice ?= instrument.price #inital price


    maximumBuyAmount = (currencyAvailable/instrument.price) * (1 - (_maximumExchangeFee/100))
    maximumSellAmount = (assetsAvailable * (1 - (_maximumExchangeFee/100)))
    
################    logging     ################

    debug "Balance ASSETS____: #{assetsAvailable} #{storage.coin}"
    debug "Balance CURRENCY__: #{currencyAvailable} USD"
    debug "Current PRICE_____: #{instrument.price} USD"    
    
    debug "Bot Gewinn________: #{(((context.currencyAvailable + (context.assetsAvailable * context.currentPrice)) / storage.startCurrency - 1)*100).toFixed(2)}%"
    debug "B&H Gewinn________: #{((context.currentPrice / storage.startPrice - 1)*100).toFixed(2)}%"     

################    SAR functions   ################
  
    sar = functions.sar(instrument.high, instrument.low, context.sarLag,context.sarAccel, context.sarAccelmax)    

    if (instrument.price >= sar)
        debug "SAR war #{context.sarCounterDOWN++}x UNTEN"
        context.sarCounterUP = 1
        plotMark
            "sarDOWN": sar

        
    if (instrument.price < sar)
        debug "SAR war #{context.sarCounterUP++}x OBEN"
        context.sarCounterDOWN = 1
        plotMark
            "sarUP": sar
             
 
 ################    Trading   ################
       
    if  context.sarCounterDOWN == 2
        trading.buy instrument, 'limit', Math.min(_maximumOrderAmount, maximumBuyAmount), instrument.price, _orderTimeout

    if context.sarCounterUP == 2
        trading.sell instrument, 'limit', Math.min(_maximumOrderAmount, maximumSellAmount), instrument.price, _orderTimeout


################    plotting    ################    




    debug " "

onStop: ->
    debug "######## BOT ENDE ########"
    debug "Start currency was__: #{storage.startCurrency} USD"
    debug "End currency is_____: #{context.currencyAvailable} USD"
    debug "Start asset was_____: #{storage.startAssets} #{storage.coin}"
    debug "End asset is________: #{context.assetsAvailable} #{storage.coin}"
    debug "Bot Gewinn__________: #{(((context.currencyAvailable + (context.assetsAvailable * context.currentPrice)) / storage.startCurrency - 1)*100).toFixed(2)}%"
    debug "B&H Gewinn__________: #{((context.currentPrice / storage.startPrice - 1)*100).toFixed(2)}%" 
#    debug "Bot started at #{new Date(storage.botStartedAt)}"
#    debug "Bot stopped at #{new Date(data.at)}"
 