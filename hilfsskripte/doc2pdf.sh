#!/bin/sh

DIR=$(pwd)
DOC=$DIR/$1
                                                                               
oowriter -invisible "macro:///Standard.Module1.ConvertWordToPDF($DOC)"

