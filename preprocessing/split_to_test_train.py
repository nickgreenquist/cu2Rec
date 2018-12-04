import argparse
import csv
import os
import random


def split_per_user(rows, train_percent):
    # create a map for each user to a list of the ratings of that user
    user_to_ratings = {}
    for rating in rows:
        userId = rating[0]
        if userId in user_to_ratings:
            user_to_ratings[userId].append(rating)
        else:
            user_to_ratings[userId] = [rating]

    train = []
    test = []
    for userId, ratings in user_to_ratings.items():
        num_ratings = len(ratings)
        random.shuffle(ratings)
        user_train = ratings[:int(num_ratings * train_percent)]
        user_test = ratings[int(num_ratings * train_percent):]

        # add user's train and test ratings to complete train/test ratings
        for rating in user_train:
            train.append(rating)
        for rating in user_test:
            test.append(rating)

    return train, test


def split_true(rows, train_percent):
    random.shuffle(rows)

    num_ratings = len(rows)
    train = rows[:int(num_ratings * train_percent)]
    test = rows[int(num_ratings * train_percent):]

    train = sorted(train, key= lambda x: x[0])
    test = sorted(test, key= lambda x: x[0])

    return train, test


def write_ratings(filename, ratings):
    with open(filename, "w", newline='') as file:
        file.write("userId,movieId,rating,timestamp\n")
        for row in ratings:
            row = [str(i) for i in row]
            line = ",".join(row)
            file.write(line)
            file.write('\n')


def read_ratings(filename):
    rows = []
    # userId,movieId,rating,timestamp
    with open(filename) as csvfile:
        readCSV = csv.reader(csvfile, delimiter=',')
        row_num = 0
        for row in readCSV:
            if row_num > 0:
                userId = int(row[0])
                movieId = int(row[1])
                rating = float(row[2])
                timestamp = int(row[3])

                rows.append([userId, movieId, rating, timestamp])
            row_num += 1
    return rows


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Splits a csv file into training and test sets")
    parser.add_argument('file_ratings', type=str, help='the path to the ratings file to split')
    parser.add_argument('test_ratio', type=float, help='the ratio of test examples')
    args = parser.parse_args()

    rows = read_ratings(args.file_ratings)
    train, test = split_true(rows, 1 - args.test_ratio)

    filepath, extension = os.path.splitext(args.file_ratings)

    write_ratings("{}_train{}".format(filepath, extension), train)
    write_ratings("{}_test{}".format(filepath, extension), test)
