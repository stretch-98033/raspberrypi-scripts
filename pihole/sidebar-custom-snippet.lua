
<br>
<span id="temperatureF">
  &nbsp;<i id="tempIconF" class="fa-solid fa-temperature-three-quarters text-green-light fa-lg" title="Loading..."></i>&nbsp;&nbsp;
  Temp: <%= 
    (function()
      local temperature_f = "N/A"
      local temperature_c = 0  -- Default numerical value
      local file = io.open("/sys/class/thermal/thermal_zone0/temp", "r")

      if file then
        temperature_c = tonumber(file:read("*a")) / 1000  -- Convert to Celsius
        file:close()
        temperature_f = string.format("%.1f°F", temperature_c * 9/5 + 32)
      end

      -- Determine CSS class and icon size based on temperature
      local color_class = "text-green-light"
      local size_class = "fa-lg"

      if temperature_c >= 80 then
        color_class = "text-red"
        size_class = "fa-2xl"  -- Make it even bigger
      elseif temperature_c >= 61 then
        color_class = "text-yellow"
        size_class = "fa-xl"  -- Slightly bigger
      end

      -- Output JavaScript to update class and size dynamically
      return temperature_f .. [[
        <script>
          document.getElementById("tempIconF").className = "fa-solid fa-temperature-three-quarters ]] .. color_class .. " " .. size_class .. [[";
          document.getElementById("tempIconF").title = "Temperature Source: /sys/class/thermal/thermal_zone0/temp";
        </script>
      ]]
    end)()
  %>
</span><br/>

<span id="temperatureC">
  &nbsp;<i id="tempIconC" class="fa-solid fa-temperature-three-quarters text-green-light fa-lg" title="Loading..."></i>&nbsp;&nbsp;
  Temp: <%= 
    (function()
      local temperature_c = "N/A"
      local numeric_temp_c = 0  -- Default numerical value
      local file = io.open("/sys/class/thermal/thermal_zone0/temp", "r")

      if file then
        numeric_temp_c = tonumber(file:read("*a")) / 1000  -- Convert to Celsius
        file:close()
        temperature_c = string.format("%.1f°C", numeric_temp_c)
      end

      -- Determine CSS class and icon size based on temperature
      local color_class = "text-green-light"
      local size_class = "fa-lg"

      if numeric_temp_c >= 80 then
        color_class = "text-red"
        size_class = "fa-2xl"  -- Make it even bigger
      elseif numeric_temp_c >= 61 then
        color_class = "text-yellow"
        size_class = "fa-xl"  -- Slightly bigger
      end

      -- Output JavaScript to update class and size dynamically
      return temperature_c .. [[
        <script>
          document.getElementById("tempIconC").className = "fa-solid fa-temperature-three-quarters ]] .. color_class .. " " .. size_class .. [[";
          document.getElementById("tempIconC").title = "Temperature Source: /sys/class/thermal/thermal_zone0/temp";
        </script>
      ]]
    end)()
  %>
</span><br/>

<span id="fanL_speed" class="text-base">
  <i id="fanIcon" class="fa-solid fa-fan text-green-light fa-lg" title="Loading..."></i>&nbsp;&nbsp;
  <span id="fanText">Fan Speed: Loading...</span>
  <%= 
    (function()
      local fan_speed = "N/A"
      local numeric_speed = 0  -- Default numerical value for comparisons
      local used_path = "Unknown"  -- Track which path is used
      local paths = {
        "/sys/devices/platform/cooling_fan/hwmon/hwmon3/fan1_input",
		"/sys/devices/platform/cooling_fan/hwmon/hwmon2/fan1_input",  -- Original path
        "/sys/devices/platform/cooling_fan/hwmon/hwmon1/fan1_input",  -- Fallback path
		
        -- Add more paths if necessary
      }

      -- Loop through each path and try to read the fan speed
      for _, path in ipairs(paths) do
        local file = io.open(path, "r")
        if file then
          local speed_str = file:read("*a")
          file:close()
          numeric_speed = tonumber(speed_str) or 0  -- Convert to number, default to 0 if invalid
          fan_speed = speed_str:gsub("%s+", "") .. " RPM"  -- Remove whitespace
          used_path = path
          break  -- Exit loop once the fan speed is successfully read
        end
      end

      -- Determine CSS class and icon/text size based on fan speed
      local color_class = "text-green-light"
      local size_class = "fa-lg"
      local text_size = "text-base"  -- Normal text size

      if numeric_speed <= 1000 then
        color_class = "text-red"
        size_class = "fa-2xl"  -- Make icon even bigger
        text_size = "text-2xl"  -- Make text larger
      elseif numeric_speed <= 1999 then
        color_class = "text-yellow"
        size_class = "fa-xl"  -- Slightly bigger icon
        text_size = "text-xl"  -- Slightly bigger text
      end

      -- Output JavaScript to update class, size, and tooltip dynamically
      return [[
        <script>
          document.getElementById("fanIcon").className = "fa-solid fa-fan ]] .. color_class .. " " .. size_class .. [[";
          document.getElementById("fanIcon").title = "Fan Speed Source: ]] .. used_path .. [[";
          document.getElementById("fanText").className = "]] .. color_class .. " " .. text_size .. [[";
          document.getElementById("fanText").innerText = "Fan Speed: ]] .. fan_speed .. [[";
        </script>
      ]]
    end)()
  %>
</span><br/>
