#!/usr/bin/env python3
import requests
import sys
from bs4 import BeautifulSoup as bs

space = '  '
base_url = 'https://dictionary.cambridge.org/dictionary/'
spellcheck_base_url = 'https://dictionary.cambridge.org/spellcheck/'
header = {'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X x.y; rv:42.0) Gecko/20100101 Firefox/42.0'}

def cambridge_get(word='hello', lang='english'):
    url = base_url + lang + '/' + word
    session = requests.Session()
    r = session.get(url, headers=header)
    return bs(r.content, 'html.parser')

def suggestions_get(word, lang='english'):
    url = spellcheck_base_url + lang + '/?q=' + word
    session = requests.Session()
    r = session.get(url, headers=header)
    soup = bs(r.content, 'html.parser')
    return soup.findAll('span', class_='prefix-item')

def print_with_limit(sentence, limit, chars=''):
    c = 1
    lb = 1
    for i in sentence.split(' '):
        if (c % limit == 0):
            print(i, sep='', end='\n')
            lb = 1
        else:
            if lb == 1:
                print(chars, sep='', end='')
                lb = 0
            print(i, sep='', end=' ')
        c += 1

def define_body(data):
    word = data.find(class_='headword').text
    try:
        type_of_words = data.find(class_='posgram ico-bg').text
    except AttributeError:
        type_of_words = ""
    descriptions = data.find_all(class_='def-block pad-indent')
    examples = data.find_all('div', class_='examp emphasized')
    return word, type_of_words, descriptions, examples

def print_body(word, type_of_words, descriptions, examples, space):
    print('{}{}{:>8}{}\n{}{}{:>10}{}'.format(
        ' ', '\x1b[7;36;40m', word.upper(), '\x1b[0m',
        '   ', '\x1b[3;36;40m', type_of_words, '\x1b[0m'))
    print('\n' + space + '\x1b[1;35;40m' + 'Definitions:' + '\x1b[0m')
    temp = []
    for i, s in enumerate(descriptions[:7]):
        try:
            description = s.find(class_='def').text
        except AttributeError:
            continue
        if description not in temp:
            print(space, i+1, '. ', description.strip().capitalize().replace(':', '.').replace('\n', ''), sep='')
            temp.append(description)
    print('\n' + space + '\x1b[1;35;40m' + 'Examples:' + '\x1b[0m')
    for i, s in enumerate(examples[:5]):
        print(space, i+1, '. ', s.text.strip().capitalize(), sep='')
    print('\n', sep='', end='')

if __name__ == '__main__':
    iswrong = False
    if len(sys.argv) == 1:
        data = cambridge_get()
    elif len(sys.argv) == 3:
        data = cambridge_get(word=sys.argv[1], lang=sys.argv[2])
    else:
        data = cambridge_get(word=sys.argv[1])

    if data.title.text == 'Cambridge English Dictionary: Meanings & Definitions':
        print('\x1b[3;36;40m' + 'I think you typed wrong :/' + '\x1b[0m')
        data = suggestions_get(sys.argv[1])
        iswrong = True

    if not iswrong:
        word, type_of_words, descriptions, examples = define_body(data)
        print_body(word, type_of_words, descriptions, examples, space * 2)
    else:
        print('\n' + space + '\x1b[1;35;40m' + 'Did you mean one of these?' + '\x1b[0m')
        for i in data:
            print(space + '\x1b[3;33;40m' + i.text + '\x1b[0m')
