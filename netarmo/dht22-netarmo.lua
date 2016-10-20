-- MQTT connect script with deep sleep
-- Remember to connect GPIO16 and RST to enable deep sleep

--############
--# Settings #
--############
properties = {}

function trim(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

function remove(s, v)
  return (string.gsub(s, v, ""))
end

print("Reading in properties...")
if file.open("sensor.properties") then
  while true 
  do 
    line = file.readline() 
    if (line == nil) then 
      file.close()
      break 
    end
    --print("Found property: "..line)
    key, value = string.match(line,"(.-)=(.-)$")
    -- We need to trim and remove extra data from the value string
    properties[key] = trim(remove(remove(value, "\n"), '"'))
  end
end

-- This is for logging purposes
--function dump(o)
--    if type(o) == 'table' then
--        local s = '{ '
--        for k,v in pairs(o) do
--                if type(k) ~= 'number' then k = '"'..k..'"' end
--                s = s .. '['..k..'] = ' .. dump(v) .. ','
--        end
--        return s .. '} '
--    else
--        return tostring(o)
--    end
--end

--- MQTT --- 
-- Values are read from sensor.properties   
--mqtt_broker_ip = "*******"
--mqtt_broker_port = 1883
--mqtt_username = ""
--mqtt_password = ""
--mqtt_client_id = "*******"
--mqtt_topic_id = "*******"

--- WIFI ---
--from properties: wifi_SSID = "*******"
--from properties: wifi_password = "*******"
-- wifi.PHYMODE_B 802.11b, More range, Low Transfer rate, More current draw
-- wifi.PHYMODE_G 802.11g, Medium range, Medium transfer rate, Medium current draw
-- wifi.PHYMODE_N 802.11n, Least range, Fast transfer rate, Least current draw 
wifi_signal_mode = wifi.PHYMODE_N
-- If the settings below are filled out then the module connects 
-- using a static ip address which is faster than DHCP and 
-- better for battery life. Blank "" will use DHCP.
-- My own tests show around 1-2 seconds with static ip
-- and 4+ seconds for DHCP

-- Client data from sensor.properties
--client_ip="192.168.1.***"
--client_netmask="255.255.255.0"
--client_gateway="192.168.1.1"

--- INTERVAL ---
-- In milliseconds. Remember that the sensor reading, 
-- reboot and wifi reconnect takes a few seconds
-- sensor.properties: time_between_sensor_readings = 300000

--################
--# END settings #
--################

-- Setup MQTT client and events
m = mqtt.Client(properties["mqtt_client_id"], 120, properties["mqtt_username"], properties["mqtt_password"])
temperature = 0
humidity = 0
voltage = 0

-- Connect to the wifi network
wifi.setmode(wifi.STATION) 
wifi.setphymode(wifi_signal_mode)
wifi.sta.config(properties["wifi_SSID"], properties["wifi_password"]) 
wifi.sta.connect()
if client_ip ~= "" then
    wifi.sta.setip({ip=properties["client_ip"],netmask=properties["client_netmask"],gateway=properties["client_gateway"]})
end

-- DHT22 sensor logic
function get_sensor_Data()
    dht=require("dht")
    status,temp,humi,temp_decimial,humi_decimial = dht.read(properties["dht22_pin"])
        if( status == dht.OK ) then
            -- Prevent "0.-2 deg C" or "-2.-6"          
            temperature = temp.."."..(math.abs(temp_decimial)/100)
            humidity = humi.."."..(math.abs(humi_decimial)/100)
            -- If temp is zero and temp_decimal is negative, then add "-" to the temperature string
            if(temp == 0 and temp_decimial<0) then
                temperature = "-"..temperature
            end
            print("Temperature: "..temperature.." deg C")
            print("Humidity: "..humidity.."%")
        elseif( status == dht.ERROR_CHECKSUM ) then          
            print( "DHT Checksum error" )
            temperature=-1 --TEST
        elseif( status == dht.ERROR_TIMEOUT ) then
            print( "DHT Time out" )
            temperature=-2 --TEST
        end
    -- Release module
    dht=nil
    package.loaded["dht"]=nil
end

function loop() 
    if wifi.sta.status() == 5 then
        -- Stop the loop
        tmr.stop(0)

        print("Connected to WIFI, connecting to MQTT")
        m:connect( properties["mqtt_broker_ip"], properties["mqtt_broker_port"], 0, function(conn)
            print("Connected to MQTT")
            print("  IP: ".. properties["mqtt_broker_ip"])
            print("  Port: ".. properties["mqtt_broker_port"])
            print("  Client ID: ".. properties["mqtt_client_id"])
            print("  Username: ".. properties["mqtt_username"])
          
            -- Get sensor data
            get_sensor_Data() 
            voltage = adc.readvdd33()
            print("System voltage/readvdd33 (mV):", voltage)
            m:publish("".. properties["mqtt_topic_id"] .. "/temperature",temperature, 0, 0, function(conn)
                m:publish("".. properties["mqtt_topic_id"] .. "/humidity",humidity, 0, 0, function(conn)
                    m:publish("".. properties["mqtt_topic_id"] .. "/voltage",humidity, 0, 0, function(conn)
                        print("Going to deep sleep for "..(properties["time_between_sensor_readings"]/1000).." seconds")
                        node.dsleep(properties["time_between_sensor_readings"]*1000)    
                    end)         
                end)          
            end)
        end )
    else
        print("Connecting...")
    end
end
        
tmr.alarm(0, 100, 1, function() loop() end)

-- Watchdog loop, will force deep sleep the operation somehow takes to long
tmr.alarm(1,4000,1,function() node.dsleep(properties["time_between_sensor_readings"]*1000) end)
