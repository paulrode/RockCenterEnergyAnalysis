# Load packages 
my_packages <- c("tidyverse", "vroom" , "janitor" , "glue" , "tsibble" , "tidytext","lubridate", "fable", "tsibbledata", "ggplot2", "forecast", "tseries", "rio", "zoo", "readxl", "tsibbledata", "knitr", "kableExtra", "formattable", "scales")
invisible( lapply(my_packages, require, character.only = TRUE))

#Set up environment 
place <- "Home"  #Where are we working today. 
# place <- "work"

if (place == "Home"){setwd("C:/Users/paulr/Documents/R/RockCenterEnergyAnalysis")} else {setwd("C:/Users/prode/Documents/R/RockCenterEnergyAnalysis")}

if (!file.exists("data")) { dir.create("data")}

rm(place, my_packages ) #Clean up

options(dplyr.summarise.inform = FALSE)  # Suppress textin Knit printout. 



# Read in data

'ElecCF' <- 0.000288962  #2021 Carbon Values
'SteamCF' <- 0.00004493 #2021 Carbon Values
'IntensityLimit24' <- 0.00846 #2024 Limit
'IntensityLimit30' <- 0.00453 #2030 Limit

SteamData <- read_excel("data/Energy_Data_for_Net_Zero_Study.xlsx", sheet = "Sheet1", range = "B2:G11" , col_names = TRUE, na = "NA", col_types = NULL ) %>%  select(-5,-6)

ElectricData <- read_excel("data/Energy_Data_for_Net_Zero_Study.xlsx", sheet = "Sheet1", range = "B13:G23" , col_names = TRUE, na = "NA", col_types = NULL ) %>% select(-5,-6)

ElectricData %>% filter(Building == '1 Rock' | Building == '600 5th') %>% 
  select( -Building) %>% 
  summarise_each(funs(sum)) %>% 
  mutate(Building = "1 Rock and 600 5th") %>% 
  select(4,1,2,3) %>% rbind(ElectricData) %>% 
  filter(Building != '1 Rock' & Building != '600 5th') -> ElectricData

BuildingGSF <- read_excel("data/Energy_Data_for_Net_Zero_Study.xlsx", sheet = "Sheet1", range = "B28:C39" , col_names = TRUE, na = "NA", col_types = NULL ) %>% 
  filter(Building != '1 Rock' & Building != '600 5th')

UtilityData <- left_join(ElectricData, SteamData, by="Building") %>% left_join(BuildingGSF, by="Building")
UtilityData[is.na(UtilityData)] <- 0


# Adding NBC Electric
All_Data <- read_excel("data/LL97 Fines Rock Center.xlsx", sheet = "NBC Energy", range = "B1:D64" , col_names = TRUE, na = "Not Available", col_types = c("guess", "guess", "numeric") ) %>% mutate(across(contains('Date'), ymd)) %>% select("Start Date", "kwh")
colnames(All_Data) <- c("Date",  "kwh")
All_Data %>% 
  group_by(year(Date)) %>% 
  summarise("Elect" = sum(kwh)) -> All_Data
colnames(All_Data) <- c("Date", "Elect")
All_Data %>% 
  filter(Date == 2019 | Date == 2020 | Date == 2021 ) -> All_Data
UtilityData[4,2] <- UtilityData[4,2] + All_Data[1,2]
UtilityData[4,3] <- UtilityData[4,3] + All_Data[2,2]
UtilityData[4,4] <- UtilityData[4,4] + All_Data[3,2]


#Campus EUI for each year 
UtilityData1 <- UtilityData 
apply(UtilityData1[2:4], 2, function(row) row * 3.4121 ) -> UtilityData1[2:4]
apply(UtilityData1[5:7], 2, function(row) row * 1194) -> UtilityData1[5:7]
UtilityData1 %>% select(`2019 kwh`, `2020 kwh`, `2021 kwh`, `2019 mlbs`, `2020 mlbs`, `2021 mlbs`, `Gross Floor Area`) %>%
  summarise_each(funs(sum)) -> UtilityData1
TotalFlArea <- UtilityData1$`Gross Floor Area`
UtilityData1 %>% 
  select(-`Gross Floor Area`) %>% 
  gather(key = "Item", value = "Value") -> UtilityData1
cbind(UtilityData1, str_split_fixed(UtilityData1$Item, " ", n=2)) %>% 
  select(-"Item") -> UtilityData1 
colnames(UtilityData1)  <-  c("Value", "Year", "Unit") 
apply(UtilityData1[3], 1, function(x) {ifelse(x == "kwh", "Elec(kBTU)", "Steam(kBTU)")}) -> UtilityData1[3]


# Make an EUI plot with kBTU vales for both  electric and steam  
UtilityData2 <- UtilityData1
apply(UtilityData2[1], 1, function(row) row / TotalFlArea ) -> UtilityData2[1]
UtilityData2 %>% 
  ggplot(aes(x = Year, y = Value, fill = Unit)) +
  geom_bar(stat = "identity", position = "stack") +
  labs( title = "Energy Use Density by fuel type for Campus",
        subtitle = "Units are kBTU's per year per Gross Squar Feet") +
  xlab("Year") +
  ylab("kBTU/SF") +
  scale_fill_manual(values = c("#CC0033", "#FFFFCC"))


### Delta's ###
UtilityData2 %>%
  group_by(Year) %>% 
  summarise("AnnuValues" = sum(Value)) %>% 
  mutate("BaseYear" = max(AnnuValues)) %>% 
  mutate("Delta" = AnnuValues/BaseYear) -> CampusDelta
CampusDelta[4] <- sapply(CampusDelta[4], function(x) percent(x, accuracy=1))



#Make a Carbon table in the dataframe UtilityData1
UtilityData3 <- UtilityData1
apply(UtilityData3[3], 1, function(x) {ifelse(x == "Elec(kBTU)", "Elect(tCO2e)", "Steam(tCO2e)")}) -> UtilityData3[3]


UtilityData3 %>% 
  mutate(Carbon = ifelse(Unit == "Elec(kBTU)", Value * ElecCF / 3.4121, Value * SteamCF)) %>% ggplot(aes(x = Year, y = Carbon, fill = Unit)) +
  geom_bar(stat = "identity", position = "stack") +
  labs( title = "Carbon Emissions by fuel type",
        subtitle = "Carbon compaired to Local Law 97 limits") +
  labs(x = "Year", y = "tCO2e") +
  #guides(fill = FALSE) +
  geom_hline(aes(yintercept = TotalFlArea * IntensityLimit24), color = "blue", linetype = "dashed", size = 0.75) +
  geom_text(aes(x = 2, y = TotalFlArea * IntensityLimit24, label = "2024 Carbon Limit"), hjust = 1, vjust = 1.25 , color = "blue") +
  geom_hline(aes(yintercept = TotalFlArea * IntensityLimit30), linetype = "dashed", color = "blue", size = 0.5, alpha = 0.5) +
  geom_text(aes(x = 2.1, y = TotalFlArea * IntensityLimit30, label = "2030 Carbon Limit", alpha = 0.1), hjust = 0, vjust = -.2 , color = "blue", alpha = 0.1) +
  scale_fill_manual(values = c("#CC0033", "#FFFFCC"))



#Plot Carbon Intensities versus LL97 Limits 
UtilityData1 <- UtilityData 
#apply(UtilityData1[2:4], 2, function(row) row * 3.4121 ) -> UtilityData1[2:4]
apply(UtilityData1[5:7], 2, function(row) row * 1194) -> UtilityData1[5:7]
UtilityData1[2:7]/UtilityData1$`Gross Floor Area` -> UtilityData1[2:7]
colnames(UtilityData1) <- c("Building", "2019 kwh", "2020 kwh", "2021 kwh", "2019 kBTUs", "2020 kBTUs", "2021 kBTUs", "Gross Floor Area")

UtilityData1 %>% select("Building", "2019 kwh", "2020 kwh", "2021 kwh", "2019 kBTUs", "2020 kBTUs", "2021 kBTUs") -> UtilityData1

UtilityData1 %>% 
  gather(key = "Item", value = "Value", -"Building") -> UtilityData1
cbind(UtilityData1, str_split_fixed(UtilityData1$Item, " ", n=2)) %>% 
  select(-"Item") -> UtilityData1 
colnames(UtilityData1)  <-  c("Building", "Value", "Year", "Unit") 
UtilityData1 %>% 
  mutate("Carbon/SF" = ifelse(Unit == "kwh", Value * ElecCF, Value * SteamCF)) %>% 
  select(Building, Year, Unit, `Carbon/SF`) %>% 
  mutate("Carbon" = "tCO2e") -> UtilityData1

UtilityData %>%   
  ggplot(aes(x = Building, y = `Gross Floor Area`, fill = Building)) +
  geom_bar(stat = "identity", position = "dodge") +
  labs( title = "Building Gross SF") +
  labs(x = "Building", y = "Gross SF") +
  theme(axis.text.x = element_text (angle = 45, vjust = 1, hjust=1)) 


UtilityData1 %>%   
  ggplot(aes(x = Year, y = `Carbon/SF`, fill = Building, group = Building)) +
  geom_bar(stat = "identity", position = "dodge") +
  labs( title = "Carbon Intensity by Building",
        subtitle = "Carbon Intensity with Local Law 97 Limtis") +
  labs(x = "Building", y = "tCO2e/sf") +
  geom_hline(aes(yintercept = IntensityLimit24), color = "blue", linetype = "dashed", size = 0.75) +
  geom_text(aes(x = 2, y = IntensityLimit24, label = "2024 Carbon Limit"), hjust = 1, vjust = 1.25 , color = "blue") +
  geom_hline(aes(yintercept = IntensityLimit30), linetype = "dashed", color = "blue", size = 0.5, alpha = 0.5) +
  geom_text(aes(x = 2, y = IntensityLimit30, label = "2030 Carbon Limit"), hjust = 0, vjust = -.2 , color = "blue", alpha = 0.01) 


CarbonLimits <- data.frame(Year = 2019:2021, IntensityLimit24 = 0.00846, IntensityLimit30 = 0.00453)
CarbonLimits$Year <- as.character(CarbonLimits$Year)



###### Making table for penalties ######
UtilityData1 %>% 
  left_join(BuildingGSF) %>% 
  left_join(CarbonLimits) %>% 
  mutate('tCO2e' = IntensityLimit24 - `Carbon/SF`) -> UtilityDataT

UtilityDataT %>% 
  mutate("Penality" = ifelse(tCO2e > 0, 0, (268 * tCO2e * UtilityDataT$`Gross Floor Area`))) -> UtilityDataT

UtilityDataT %>% 
  filter(Year == 2019) %>% 
  select(-Year, -Unit, -Carbon, -IntensityLimit30, -IntensityLimit24) %>% 
  group_by(Building) %>% 
  summarise( "CarbonPSF" = sum(`Carbon/SF`), "tCO2e" = sum(`tCO2e`), "Penalty" = sum(Penality))  -> UtilityDataT2

kable(UtilityDataT2, col.names = c("Building", "Carbon/GSF", "Total Carbon", "Net Penanity"), align = "lllc", caption = "<center><strong><strong>Penality Tabulation</strong></strong></center>", digits = getOption("digits"),  "simple") 



#1 Electric kWh
ElectricData %>% select(Building, `2019 kwh`, `2020 kwh`, `2021 kwh`) %>% 
  gather(key = "Item", value = "Value", -Building) %>%
  ggplot(aes(x = Building, y = Value, fill = Item, group = Item)) +
  labs( title = "Annual Electric by Building",
        subtitle = "2019 and Covid years", x = "Building", y = "kWh") +
  theme(axis.text.x = element_text (angle = 45, vjust = 1, hjust=1)) +
  geom_bar(stat = "identity", position = "dodge")



#2 Electric kWh per GSF 
UtilityData1 <- UtilityData
apply(UtilityData1[2:7], 2, function(row) row / UtilityData1$`Gross Floor Area`) -> UtilityData1[2:7]
UtilityData1 %>% select(Building, `2019 kwh`, `2020 kwh`, `2021 kwh`) %>% 
  gather(key = "Item", value = "Value", -Building) %>% 
  ggplot(aes(x = Building, y = Value, fill = Item, group = Item)) +
  labs( title = "Annual Electric per Gross Squar Foot by Building",
        subtitle = "2019 and Covid years", x = "Building", y = "kWh/GSF") +
  theme(axis.text.x = element_text (angle = 45, vjust = 1, hjust=1)) +
  geom_bar(stat = "identity", position = "dodge")



#3 percent kWh reductions relative to 2019 
UtilityData1 <- UtilityData
apply(UtilityData1[2:7], 2, function(row) row / UtilityData1$`Gross Floor Area`) -> UtilityData1[2:7]
apply(UtilityData1[2:4], 2, function(row) row / UtilityData1$`2019 kwh`) -> UtilityData1[2:4]
UtilityData1 %>% select(Building, `2019 kwh`, `2020 kwh`, `2021 kwh`) %>% 
  gather(key = "Item", value = "Value", -Building) %>% 
  ggplot(aes(x = Building, y = Value, fill = Item, group = Item)) + 
  labs( title = "Percent of 2019 Electrical Consumption by Building",
        subtitle = "2019 Electric versys Covid years", x = "Building", y = "kWh/GSF % of 2019") +
  theme(axis.text.x = element_text (angle = 45, vjust = 1, hjust=1)) +
  geom_bar(stat = "identity", position = "dodge")




# 4 Steam mlb 
SteamData %>% select(Building, `2019 mlbs`, `2020 mlbs`, `2021 mlbs`) %>% 
  gather(key = "Item", value = "Value", -Building) %>%
  ggplot(aes(x = Building, y = Value, fill = Item, group = Item)) +
  labs( title = "Steam Comsumption ",
        subtitle = "Steam comsumption in mLB per year and building", x = "Building", y = "Mlb") +
  theme(axis.text.x = element_text (angle = 45, vjust = 1, hjust=1)) +
  geom_bar(stat = "identity", position = "dodge")




#5 steam mlb per gsf 
UtilityData1 <- UtilityData
apply(UtilityData1[2:7], 2, function(row) row / UtilityData1$`Gross Floor Area`) -> UtilityData1[2:7]
UtilityData1 %>% select(Building, `2019 mlbs`, `2020 mlbs`, `2021 mlbs`) %>% 
  gather(key = "Item", value = "Value", -Building) %>% 
  ggplot(aes(x = Building, y = Value, fill = Item, group = Item)) +
  labs( title = "Steam Comsumption per GSF ",
        subtitle = "Steam comsumption in mLB per GSF year and building", x = "Building", y = "Mlb/GSF") +
  theme(axis.text.x = element_text (angle = 45, vjust = 1, hjust=1)) +
  geom_bar(stat = "identity", position = "dodge")






#6 percent down from 2019
UtilityData1 <- UtilityData
apply(UtilityData1[2:7], 2, function(row) row / UtilityData1$`Gross Floor Area`) -> UtilityData1[2:7]
apply(UtilityData1[5:7], 2, function(row) row / UtilityData1$`2019 mlbs`) -> UtilityData1[5:7]
UtilityData1 %>% select(Building, `2019 mlbs`, `2020 mlbs`, `2021 mlbs`) %>% 
  gather(key = "Item", value = "Value", -Building) %>% 
  ggplot(aes(x = Building, y = Value, fill = Item, group = Item)) +
  labs( title = "Percent of 2019 Steam Consumption by Building ",
        subtitle = "2019 Steam versys Covid years", x = "Building", y = "Mlb/GSF % of 2019") +
  theme(axis.text.x = element_text (angle = 45, vjust = 1, hjust=1)) +
  geom_bar(stat = "identity", position = "dodge")




EPA_data <- read_excel("data/EPA_Annual_Energy_Use_By_Meter.xlsx", range = "A6:BB155" , col_names = FALSE, na = "NA", col_types = NULL )

EPA_data <- read_excel("data/EPA_Annual_Energy_Use_By_Meter.xlsx", skip = 4)




Turnstile_data <- read.csv("data/RC_Occunpancy_Data_Details_data.csv") %>% 
  select(Property, Date, Total.Entrants)

Turnstile_data$Date <- mdy(Turnstile_data$Date)

Turnstile_data %>%   
  group_by(Property, "Year" = year(Date)) %>%  #"Month" = month(Date)) %>% 
  summarise(Population = sum(Total.Entrants)) -> Turnstile_data1
Turnstile_data1$Year <- as.factor(Turnstile_data1$Year)

Turnstile_data1 %>% 
  ggplot(aes(x = Property, y = Population, group = Year, fill = Year)) +
  labs( title = "Turnstyle Counts by Month",
        subtitle = "Morning Counts", x = "Building", y = "Entrants") +
  theme(axis.text.x = element_text (angle = 45, vjust = 1, hjust=1)) +
  geom_bar(stat = "identity", position = "dodge")





Turnstile_data %>%   
  group_by("Year" = year(Date)) %>%   
  summarise(Population = sum(Total.Entrants)) -> Turnstile_data2
Turnstile_data2$Year <- as.factor(Turnstile_data2$Year)



