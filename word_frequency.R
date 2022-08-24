library(tidyverse)
library(tidytext)
library(readtext)
library(magrittr)

df <- read.csv("C:/Users/jliebert/Downloads/Untitled spreadsheet - Sheet1 (1).csv", header=FALSE)

new_df <- df %>% unnest_tokens(word, V1)
freq_df <- new_df %>% count(word) %>% arrange(desc(n))