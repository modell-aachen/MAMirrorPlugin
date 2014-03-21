USERPLUGINS=$1

MAXSIZE=9500000

PLUGINS1=''
PLUGINS2=''
PLUGINS3=''

# get rms login
echo "Please enter customer:"
read CUSTOMER
test -z "$CUSTOMER" && {
    echo "No customer entered"
    exit 1;
}

echo "Please enter password:"
read -s PASS
test -z "$PASS" && {
    echo "No password entered"
    exit 1;
}

test -e pluginlist.txt && {
    rm pluginlist.txt || exit 1;
}
test -z "$USERPLUGINS" && {
    echo
    echo "Getting list of plugins..."
    wget -q -O - "http://updates.modell-aachen.de/FastReport?skin=text&username=$CUSTOMER&password=$PASS" | grep '{ topic: .*' | sed -e 's#{ topic: ##' > pluginlist.txt
    test -s pluginlist.txt || {
        echo "Error getting list of plugins"
        exit 1;
    }
} || {
    echo "$USERPLUGINS" > pluginlist.txt
    test -s pluginlist.txt || {
        echo "Error writing list of plugins"
        exit 1;
    }
}

echo
echo "Downloading Plugins..."
for plugin in `cat pluginlist.txt | grep -v SolrPlugin`; do # XXX hardcoded SolrPlugin as an exception here, since it will be too big
    echo "$plugin"

    # cleanup
    test -e "${plugin}.tgz" && {
        rm "${plugin}.tgz" -f || exit 1;
    }
    test -e "${plugin}.txt" && {
        rm "${plugin}.txt" -f || exit 1;
    }
    test -e "${plugin}_installer" && {
        rm "${plugin}_installer" -f || exit 1;
    }

    # download & extraction
    wget -q -O "${plugin}.tgz" "http://updates.modell-aachen.de/pub/${plugin}/${plugin}.tgz?username=$CUSTOMER&password=$PASS"
    test -s "${plugin}.tgz" || {
        echo "Error getting tgz for $plugin"
        exit 1;
    }
    test 
    tar -xf "${plugin}.tgz" "data/System/${plugin}.txt" --strip-components=2
    test -s "${plugin}.txt" || {
        echo "Error extracting txt for $plugin"
        exit 1;
    }
    tar -xf "${plugin}.tgz" "${plugin}_installer"
    test -s "${plugin}_installer" || {
        echo "Error extracting installer for $plugin"
        exit 1;
    }

    # decide which archive to put it into
    TOTAR="${plugin}.tgz ${plugin}.txt ${plugin}_installer"
    TMP=`du -bc $PLUGINS1 $TOTAR | grep total | grep -o '[0-9]*'`
    test $TMP -ge $MAXSIZE && {
        TMP=`du -bc $PLUGINS2 $TOTAR | grep total | grep -o '[0-9]*'`
        test $TMP -ge $MAXSIZE && {
            TMP=`du -bc $PLUGINS3 $TOTAR | grep total | grep -o '[0-9]*'`
            test $TMP -ge $MAXSIZE && {
                echo "Too much plugin!"
                echo "PLUGINS1: $PLUGINS1 with " `du -bc $PLUGINS1 | grep total`
                echo "PLUGINS2: $PLUGINS2 with " `du -bc $PLUGINS2 | grep total`
                echo "PLUGINS3: $PLUGINS3 $TOTAR with " `du -bc $PLUGINS3 $TOTAR | grep total`
                exit 1;
            }
            PLUGINS3="$PLUGINS3 $TOTAR";
        } || {
            PLUGINS2="$PLUGINS2 $TOTAR";
        }
    } || {
        PLUGINS1="$PLUGINS1 $TOTAR";
    }
done

# create tar files
echo
echo "Compiling tar files..."
test -e plugins1.tar && { rm plugins1.tar || exit 1; }
test -e plugins2.tar && { rm plugins2.tar || exit 1; }
test -e plugins3.tar && { rm plugins3.tar || exit 1; }
# XXX make this a function
test -n "$PLUGINS1" && {
    echo "plugins1.tar"
    tar -cf plugins1.tar $PLUGINS1
    test -s plugins1.tar || {
        echo "Error creating plugins1.tar with $PLUGINS1"
        exit 1;
    }
}
test -n "$PLUGINS2" && {
    echo "plugins2.tar"
    tar -cf plugins2.tar $PLUGINS2
    test -s plugins2.tar || {
        echo "Error creating plugins2.tar with $PLUGINS2"
        exit 1;
    }
}
test -n "$PLUGINS3" && {
    echo "plugins3.tar"
    tar -cf plugins3.tar $PLUGINS3
    test -s plugins3.tar || {
        echo "Error creating plugins3.tar with $PLUGINS3"
        exit 1;
    }
}

echo
echo "finished"
