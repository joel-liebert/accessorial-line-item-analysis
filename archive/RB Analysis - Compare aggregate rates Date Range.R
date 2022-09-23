---
title: "Untitled"
author: "Ray Boaz"
date: "2022-08-26"
output: html_document
---
---
editor_options:
  markdown:
    wrap: 72
title: Contract Rates - Accessorial Analysis
---

# packages

```{r, echo = f}
library(bigrquery)
library(DBI)
library(dplyr)

bqcon <- dbConnect(
  bigrquery::bigquery(),
  project = "freightwaves-data-science"
)

bj <- dbGetQuery(bqcon, "Select *
From(
  select *, 
  case 
    when transportation_mode_description in ('TRUCKLOAD (DRY VAN)', 'TRUCKLOAD', 'MOTOR', 'BROKER') then 'VAN'
    when transportation_mode_description = 'TRUCKLOAD (TEMP-CONTROLLED)'then 'REEFER'
    else
      'Other'
    end
    as mode
    from `freightwaves-data-factory.warehouse.beetlejuice`)
where mode in ('VAN', 'REEFER') and ship_date >= '2021-07-01'
")
```

#Check most common accessorials

```{r, echo = F}
accessorial_table <- bj %>% 
  group_by(accessorial_charge_description, mode) %>% 
  tally() %>% arrange(desc(n)) %>% 
print(accessorial_table)
```

#Create base / fuel / accessorial individual line item charge columns

```{r, echo = F}
base_total <- bj %>% 
  mutate(LOH = cut(distance,
                   c(0,100, 250, 500, 750, 1000, 1500,10000),
                   labels = c('City', 'Short', 'Mid', 'Tweener', 'Long', 'Extra-Long', 'Cross Country'))) %>% 
  group_by(cass_shipment_id, mode, origin_postal_code, destination_postal_code, LOH) %>%
  filter(!grepl('BASE', accessorial_charge_description)) %>%
  summarize(non_base_total = sum(accessorial_charge_amount), total = max(amount_paid)) %>%
  mutate(Base_Rate = total - non_base_total)

fuel_total <- bj %>% group_by(cass_shipment_id, mode, origin_postal_code, destination_postal_code) %>%
  filter(grepl('FUEL|ENERGY', accessorial_charge_description)) %>%
  summarize(fuel_total = sum(accessorial_charge_amount))

other_total <- bj %>% group_by(cass_shipment_id, mode, origin_postal_code, destination_postal_code) %>%
  filter(!grepl('BASE|FUEL|ENERGY', accessorial_charge_description)) %>%
  summarize(other_total = sum(accessorial_charge_amount))

targeted_total <- bj %>% group_by(cass_shipment_id, mode, origin_postal_code, destination_postal_code) %>%
  filter(grepl('PICKUP|DELIVERY|LOADING|USED|TOLL|TAX|CUSTOMS|TAX|BORDER|COMPLIANCE|MANAGEMENT|MISCELL|DUTY|CARBON', accessorial_charge_description)) %>%
  summarize(targeted_total = sum(accessorial_charge_amount))

all_data <- base_total %>% select(cass_shipment_id, mode,LOH, origin_postal_code, destination_postal_code, total, non_base_total, Base_Rate) %>% 
  left_join(., fuel_total, by = c('cass_shipment_id' = 'cass_shipment_id')) %>% 
  left_join(., other_total, by = c('cass_shipment_id' = 'cass_shipment_id')) %>% 
  left_join(., targeted_total, by = c('cass_shipment_id' = 'cass_shipment_id')) %>%
  mutate(Base_Fuel = Base_Rate + fuel_total,
         Base_Fuel_Targeted = Base_Rate + fuel_total + targeted_total) %>% 
  rename(mode = mode.x) %>%
  mutate(origin_zip3 = substr(origin_postal_code.x, 1, 3), 
         dest_zip3 = substr(destination_postal_code.x, 1, 3)) %>%
  select(cass_shipment_id, mode, LOH, origin_zip3, dest_zip3, total, non_base_total, Base_Rate, fuel_total, other_total, targeted_total, Base_Fuel, Base_Fuel_Targeted)
```

#Variance by mode by lane for each 
```{r, echo = F} 
var_df <- all_data %>% group_by(mode, origin_zip3, dest_zip3, LOH) %>%
  summarize(Var_Base = var(Base_Rate), 
            Var_Base_Fuel = var(Base_Fuel),
            Var_Base_Fuel_Targeted = var(Base_Fuel_Targeted),
            Var_Total = var(total),
            Count = n())

#Average Lane Variance by mode
med_var_df <- var_df %>% group_by(mode, LOH) %>%
  summarize( `Lane Count` = n(), 
             Med_Var_Base = median(Var_Base, na.rm = T), 
            Med_Var_Base_Fuel = median(Var_Base_Fuel, na.rm = T),
            Med_Var_Base_Fuel_Targeted = median(Var_Base_Fuel_Targeted, na.rm = T),
            Med_Var_Total = median(Var_Total, na.rm = T)
           ) %>% 
  tidyr::pivot_longer(., cols = 4:ncol(.), names_to = 'Rate Type', values_to = 'Median Variance') %>%
  mutate(`Median Variance` = scales::comma(`Median Variance`))


print(med_var_df)
```